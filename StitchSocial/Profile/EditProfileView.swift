//
//  EditProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Complete Profile Editing Interface
//  Dependencies: SwiftUI, PhotosUI, UserService, BasicUserInfo
//  Features: Text editing, image upload, validation, save/cancel
//

import SwiftUI
import PhotosUI

struct NewEditProfileView: View {
    
    // MARK: - Dependencies
    
    @ObservedObject var userService: UserService
    let currentUser: BasicUserInfo
    let onSave: (BasicUserInfo) -> Void
    
    // MARK: - State
    
    @State private var displayName: String
    @State private var username: String
    @State private var bio: String
    @State private var isPrivate: Bool
    
    // Image handling
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImageData: Data?
    @State private var showingImagePicker = false
    
    // UI state
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false
    
    // Validation
    @State private var usernameError: String?
    @State private var displayNameError: String?
    @State private var bioError: String?
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Initialization
    
    init(userService: UserService, currentUser: BasicUserInfo, onSave: @escaping (BasicUserInfo) -> Void) {
        self.userService = userService
        self.currentUser = currentUser
        self.onSave = onSave
        
        // Initialize state with current values
        _displayName = State(initialValue: currentUser.displayName)
        _username = State(initialValue: currentUser.username)
        _bio = State(initialValue: currentUser.bio ?? "")
        _isPrivate = State(initialValue: currentUser.isPrivate ?? false)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isSaving {
                    savingView
                } else {
                    editingContent
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                await loadSelectedImage()
            }
        }
        .onChange(of: displayName) { _ in checkForChanges() }
        .onChange(of: username) { _ in
            checkForChanges()
            validateUsername()
        }
        .onChange(of: bio) { _ in
            checkForChanges()
            validateBio()
        }
        .onChange(of: isPrivate) { _ in checkForChanges() }
    }
    
    // MARK: - Main Content
    
    private var editingContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // Navigation Header
                navigationHeader
                
                // Profile Image Section
                profileImageSection
                
                // Form Fields
                formFields
                
                // Privacy Toggle
                privacySection
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Navigation Header
    
    private var navigationHeader: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.gray)
            
            Spacer()
            
            Text("Edit Profile")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Spacer()
            
            Button("Save") {
                Task {
                    await saveProfile()
                }
            }
            .foregroundColor(hasChanges && isFormValid ? .cyan : .gray)
            .fontWeight(.semibold)
            .disabled(!hasChanges || !isFormValid)
        }
        .padding(.top, 10)
    }
    
    // MARK: - Profile Image Section
    
    private var profileImageSection: some View {
        VStack(spacing: 16) {
            
            // Current/New Image
            ZStack {
                if let imageData = profileImageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else if let profileImageURL = currentUser.profileImageURL, !profileImageURL.isEmpty {
                    AsyncImage(url: URL(string: profileImageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
                
                // Edit overlay
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    )
            }
            .onTapGesture {
                showingImagePicker = true
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
            
            Text("Tap to change photo")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Form Fields
    
    private var formFields: some View {
        VStack(spacing: 20) {
            
            // Display Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                TextField("Your display name", text: $displayName)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .autocapitalization(.words)
                
                if let error = displayNameError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Username
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                TextField("@username", text: $username)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                
                if let error = usernameError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("This is how others will find you")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Bio
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bio")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(bio.count)/150")
                        .font(.caption)
                        .foregroundColor(bio.count > 150 ? .red : .gray)
                }
                
                TextField("Tell people about yourself...", text: $bio, axis: .vertical)
                    .textFieldStyle(ProfileTextFieldStyle())
                    .lineLimit(3...6)
                
                if let error = bioError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Account")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text("Only approved followers can see your content")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Toggle("", isOn: $isPrivate)
                    .toggleStyle(SwitchToggleStyle(tint: .cyan))
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Saving View
    
    private var savingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.cyan)
                .scaleEffect(1.2)
            
            Text("Saving profile...")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Validation
    
    private func validateUsername() {
        usernameError = nil
        
        if username.isEmpty {
            usernameError = "Username cannot be empty"
            return
        }
        
        if username.count < 3 {
            usernameError = "Username must be at least 3 characters"
            return
        }
        
        if username.count > 20 {
            usernameError = "Username must be 20 characters or less"
            return
        }
        
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if username.unicodeScalars.contains(where: { !validCharacters.contains($0) }) {
            usernameError = "Username can only contain letters, numbers, and underscores"
            return
        }
    }
    
    private func validateDisplayName() {
        displayNameError = nil
        
        if displayName.isEmpty {
            displayNameError = "Display name cannot be empty"
            return
        }
        
        if displayName.count > 30 {
            displayNameError = "Display name must be 30 characters or less"
            return
        }
    }
    
    private func validateBio() {
        bioError = nil
        
        if bio.count > 150 {
            bioError = "Bio must be 150 characters or less"
            return
        }
    }
    
    private var isFormValid: Bool {
        return usernameError == nil &&
               displayNameError == nil &&
               bioError == nil &&
               !username.isEmpty &&
               !displayName.isEmpty
    }
    
    // MARK: - Change Detection
    
    private func checkForChanges() {
        hasChanges = displayName != currentUser.displayName ||
                    username != currentUser.username ||
                    bio != (currentUser.bio ?? "") ||
                    isPrivate != (currentUser.isPrivate ?? false) ||
                    profileImageData != nil
        
        // Validate on change
        validateDisplayName()
    }
    
    // MARK: - Image Handling
    
    private func loadSelectedImage() async {
        guard let selectedPhotoItem = selectedPhotoItem else { return }
        
        do {
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self) {
                await MainActor.run {
                    self.profileImageData = data
                    checkForChanges()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load image: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    // MARK: - Save Profile
    
    private func saveProfile() async {
        guard isFormValid else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        do {
            var imageURL: String? = currentUser.profileImageURL
            
            // Upload new image if selected
            if let imageData = profileImageData {
                imageURL = try await userService.updateProfileImage(
                    userID: currentUser.id,
                    imageData: imageData
                )
            }
            
            // Update profile data
            try await userService.updateProfile(
                userID: currentUser.id,
                displayName: displayName,
                bio: bio.isEmpty ? nil : bio,
                isPrivate: isPrivate,
                username: username != currentUser.username ? username : nil
            )
            
            // Create updated user info
            let updatedUser = BasicUserInfo(
                id: currentUser.id,
                username: username,
                displayName: displayName,
                bio: bio.isEmpty ? "" : bio,
                tier: currentUser.tier,
                clout: currentUser.clout,
                isVerified: currentUser.isVerified,
                isPrivate: isPrivate,
                profileImageURL: imageURL ?? "",
                createdAt: currentUser.createdAt
            )
            
            await MainActor.run {
                isSaving = false
                onSave(updatedUser)
                dismiss()
            }
            
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = "Failed to save profile: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - Custom Text Field Style

struct ProfileTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.15))
            )
            .foregroundColor(.white)
            .font(.body)
    }
}

// MARK: - Preview

#Preview {
    NewEditProfileView(
        userService: UserService(),
        currentUser: BasicUserInfo(
            id: "test",
            username: "testuser",
            displayName: "Test User",
            bio: "This is a test bio",
            tier: .rookie,
            clout: 100,
            isVerified: false,
            profileImageURL: ""
        )
    ) { user in
        // Handle save callback
    }
}
