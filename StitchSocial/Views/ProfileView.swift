//
//  ProfileView.swift
//  StitchSocial
//
//  Layer 8: Views - Optimized Profile Display with Fixed Video Grid and Refresh
//  Dependencies: ProfileViewModel (Layer 7), VideoThumbnailView, EditProfileView
//  Features: Lightweight thumbnails, profile refresh, proper video playback, thumbnail caching
//

import SwiftUI
import PhotosUI

struct ProfileView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var viewModel: ProfileViewModel
    private let userService: UserService
    
    // MARK: - UI State
    
    @State private var scrollOffset: CGFloat = 0
    @State private var showStickyTabBar = false
    @State private var showingFollowingList = false
    @State private var showingFollowersList = false
    @State private var showingSettings = false
    @State private var showingEditProfile = false
    @State private var showingVideoPlayer = false
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var selectedVideoIndex = 0
    
    // MARK: - Video Deletion State
    
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CoreVideoMetadata?
    @State private var isDeletingVideo = false
    
    // MARK: - Bio State
    
    @State private var isShowingFullBio = false
    
    // MARK: - Initialization
    
    init(authService: AuthService, userService: UserService, videoService: VideoService? = nil) {
        let videoSvc = videoService ?? VideoService()
        self.userService = userService
        self._viewModel = StateObject(wrappedValue: ProfileViewModel(
            authService: authService,
            userService: userService,
            videoService: videoSvc
        ))
    }

// MARK: - Edit Profile View Implementation

struct EditProfileView: View {
    
    // MARK: - Dependencies
    
    let userService: UserService
    @Binding var user: BasicUserInfo
    
    // MARK: - Form State
    
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var isPrivate: Bool = false
    
    // MARK: - Image Picker State
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImageData: Data?
    @State private var profileImageURL: String?
    
    // MARK: - UI State
    
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        profileImageSection
                        formSection
                        privacySection
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
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveProfile() }
                    }
                    .foregroundColor(hasChanges ? .cyan : .gray)
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || isLoading)
                }
            }
        }
        .onAppear {
            loadCurrentProfile()
        }
        .onChange(of: selectedPhoto) { _, newPhoto in
            loadSelectedPhoto(newPhoto)
        }
        .onChange(of: displayName) { _, _ in checkForChanges() }
        .onChange(of: username) { _, _ in checkForChanges() }
        .onChange(of: bio) { _, _ in checkForChanges() }
        .onChange(of: isPrivate) { _, _ in checkForChanges() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
    }
    
    // MARK: - Profile Image Section
    
    private var profileImageSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Profile image
                if let profileImageURL = profileImageURL, !profileImageURL.isEmpty {
                    AsyncImage(url: URL(string: profileImageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            )
                    }
                } else if let originalURL = user.profileImageURL, !originalURL.isEmpty {
                    AsyncImage(url: URL(string: originalURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.title)
                                    .foregroundColor(.gray)
                            )
                    }
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            Text(user.displayName.prefix(2).uppercased())
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        )
                }
                
                // Edit button overlay
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }
                .offset(x: 40, y: 40)
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
            )
            
            Text("Tap to change photo")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Form Section
    
    private var formSection: some View {
        VStack(spacing: 20) {
            // Display Name
            formField(
                title: "Display Name",
                text: $displayName,
                placeholder: "Enter display name",
                maxLength: 50
            )
            
            // Username
            formField(
                title: "Username",
                text: $username,
                placeholder: "Enter username",
                maxLength: 20,
                prefix: "@"
            )
            
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
                
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 100)
                    
                    TextEditor(text: $bio)
                        .font(.body)
                        .foregroundColor(.white)
                        .background(Color.clear)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                    
                    if bio.isEmpty {
                        Text("Tell people about yourself...")
                            .font(.body)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
    
    // MARK: - Privacy Section
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy")
                .font(.headline)
                .foregroundColor(.white)
            
            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Account")
                        .font(.body)
                        .foregroundColor(.white)
                    
                    Text("Only followers can see your videos")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Form Field Helper
    
    private func formField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        maxLength: Int,
        prefix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(text.wrappedValue.count)/\(maxLength)")
                    .font(.caption)
                    .foregroundColor(text.wrappedValue.count > maxLength ? .red : .gray)
            }
            
            HStack {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.body)
                        .foregroundColor(.gray)
                }
                
                TextField(placeholder, text: text)
                    .font(.body)
                    .foregroundColor(.white)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: text.wrappedValue) { _, newValue in
                        if newValue.count > maxLength {
                            text.wrappedValue = String(newValue.prefix(maxLength))
                        }
                    }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(text.wrappedValue.count > maxLength ? .red : Color.clear, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                
                Text("Saving profile...")
                    .font(.headline)
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
    
    // MARK: - Methods
    
    private func loadCurrentProfile() {
        displayName = user.displayName
        username = user.username
        profileImageURL = user.profileImageURL
        
        // Load extended profile data for bio and privacy
        Task {
            do {
                if let profile = try await userService.getExtendedProfile(id: user.id) {
                    await MainActor.run {
                        bio = profile.bio
                        isPrivate = profile.isPrivate
                    }
                }
            } catch {
                print("Failed to load extended profile: \(error)")
            }
        }
    }
    
    private func loadSelectedPhoto(_ photoItem: PhotosPickerItem?) {
        guard let photoItem = photoItem else { return }
        
        Task {
            do {
                if let data = try await photoItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        profileImageData = data
                        // Create temporary URL for preview
                        profileImageURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
                        checkForChanges()
                    }
                }
            } catch {
                await MainActor.run {
                    showError("Failed to load selected photo: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkForChanges() {
        let hasDisplayNameChanged = displayName != user.displayName
        let hasUsernameChanged = username != user.username
        let hasImageChanged = profileImageData != nil
        
        // Check bio changes by loading current bio and comparing
        Task {
            do {
                if let profile = try await userService.getExtendedProfile(id: user.id) {
                    await MainActor.run {
                        let hasBioChanged = bio != profile.bio
                        let hasPrivacyChanged = isPrivate != profile.isPrivate
                        
                        hasChanges = hasDisplayNameChanged || hasUsernameChanged ||
                                   hasImageChanged || hasBioChanged || hasPrivacyChanged
                    }
                }
            } catch {
                // If we can't load profile, just check basic fields
                await MainActor.run {
                    hasChanges = hasDisplayNameChanged || hasUsernameChanged || hasImageChanged
                }
            }
        }
    }
    
    private func saveProfile() async {
        guard hasChanges else { return }
        
        isLoading = true
        
        do {
            // Upload new profile image if selected
            var newImageURL: String? = nil
            if let imageData = profileImageData {
                newImageURL = try await userService.uploadProfileImage(
                    userID: user.id,
                    imageData: imageData
                )
                print("Profile image uploaded: \(newImageURL ?? "nil")")
            }
            
            // Update profile data
            try await userService.updateProfile(
                userID: user.id,
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                isPrivate: isPrivate,
                username: username.isEmpty ? nil : username
            )
            
            // Update local user object
            await MainActor.run {
                user = BasicUserInfo(
                    id: user.id,
                    username: username.isEmpty ? user.username : username,
                    displayName: displayName.isEmpty ? user.displayName : displayName,
                    tier: user.tier,
                    clout: user.clout,
                    isVerified: user.isVerified,
                    profileImageURL: newImageURL ?? user.profileImageURL,
                    createdAt: user.createdAt
                )
                
                // Notify ProfileView to refresh its data
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshProfile"),
                    object: nil,
                    userInfo: ["userID": user.id]
                )
                
                isLoading = false
                dismiss()
            }
            
            print("Profile updated successfully")
            
        } catch {
            await MainActor.run {
                isLoading = false
                showError("Failed to save profile: \(error.localizedDescription)")
            }
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}
    
    // MARK: - Main Body
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else if let user = viewModel.currentUser {
                profileContent(user: user)
            } else {
                noUserView
            }
        }
        .task {
            await viewModel.loadProfile()
        }
        .onAppear {
            // Start profile animations when user is loaded
            if let user = viewModel.currentUser {
                let hypeProgress = CGFloat(viewModel.calculateHypeProgress())
                viewModel.animationController.startEntranceSequence(hypeProgress: hypeProgress)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshProfile"))) { _ in
            Task {
                await viewModel.refreshProfile()
            }
        }
        .sheet(isPresented: $showingFollowingList) {
            followingSheet
        }
        .sheet(isPresented: $showingFollowersList) {
            followersSheet
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showingEditProfile) {
            editProfileSheet
        }
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            fullScreenVideoPlayer
        }
        .alert("Delete Video", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performVideoDelete() }
            }
        } message: {
            if let video = videoToDelete {
                Text("Are you sure you want to delete '\(video.title)'? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Profile Content
    
    private func profileContent(user: BasicUserInfo) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    optimizedProfileHeader(user: user)
                    tabBarSection
                    videoGridSection
                }
                .background(scrollTracker)
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                handleScrollChange(value)
            }
            .overlay(alignment: .top) {
                if showStickyTabBar {
                    stickyTabBar
                }
            }
        }
    }
    
    // MARK: - Optimized Profile Header
    
    private func optimizedProfileHeader(user: BasicUserInfo) -> some View {
        VStack(spacing: 20) {
            // Section 1: Profile Image & Basic Info
            HStack(spacing: 16) {
                enhancedProfileImage(user: user)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Name and verification
                    HStack(spacing: 8) {
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.red) // RED VERIFIED BADGE
                        }
                    }
                    
                    // Username
                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    // Tier badge
                    tierBadge(user: user)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Section 2: Bio (Full Width)
            if shouldShowBio(user: user) {
                VStack(alignment: .leading, spacing: 8) {
                    bioSection(user: user)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }
            
            // Section 3: PROMINENT HYPE METER (Full Width)
            VStack(spacing: 12) {
                hypeMeterSection(user: user)
            }
            .padding(.horizontal, 20)
            
            // Section 4: Stats Row
            statsRow(user: user)
            
            // Section 5: Action Buttons
            actionButtonsRow(user: user)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Hype Meter Section (PROMINENT)
    
    private func hypeMeterSection(user: BasicUserInfo) -> some View {
        let hypeRating = calculateHypeRating(user: user)
        let progress = CGFloat(hypeRating / 100.0)
        
        return VStack(spacing: 8) {
            // Title and percentage
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Hype Rating")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(hypeRating))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Progress bar with shimmer
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 12)
                        .overlay(
                            // Shimmer effect
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.6), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .offset(x: viewModel.animationController.shimmerOffset)
                        )
                }
            }
            .frame(height: 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .onAppear {
            print("🔥 HYPE METER SECTION APPEARED: Rating \(Int(hypeRating))%")
            viewModel.animationController.startEntranceSequence(hypeProgress: progress)
        }
    }
    
    // MARK: - Bio Section
    
    private func bioSection(user: BasicUserInfo) -> some View {
        Group {
            if let bio = getBioForUser(user), !bio.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bio)
                        .font(.body)
                        .foregroundColor(.white)
                        .lineLimit(isShowingFullBio ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if bio.count > 80 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isShowingFullBio.toggle()
                            }
                        }) {
                            Text(isShowingFullBio ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else if viewModel.isOwnProfile {
                Button(action: { showingEditProfile = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.8))
                        
                        Text("Add bio")
                            .font(.body)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Enhanced Profile Image
    
    private func enhancedProfileImage(user: BasicUserInfo) -> some View {
        ZStack {
            // Progress ring background
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                .frame(width: 90, height: 90)
            
            // Clout progress ring
            Circle()
                .trim(from: 0, to: viewModel.calculateHypeProgress())
                .stroke(
                    LinearGradient(
                        colors: getTierColors(user.tier),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))
            
            // Profile image
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
        }
    }
    
    // MARK: - Tier Badge
    
    private func tierBadge(user: BasicUserInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: getTierIcon(user.tier))
                .font(.caption)
                .foregroundColor(getTierColors(user.tier).first ?? .white)
            
            Text(user.tier.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: getTierColors(user.tier),
                startPoint: .leading,
                endPoint: .trailing
            ).opacity(0.3)
        )
        .background(Color.black.opacity(0.5))
        .cornerRadius(10)
    }
    
    // MARK: - Stats Row
    
    private func statsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 30) {
            statItem(title: "Videos", value: "\(viewModel.userVideos.count)")
            
            Button(action: { showingFollowersList = true }) {
                statItem(title: "Followers", value: "\(viewModel.followersList.count)")
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: { showingFollowingList = true }) {
                statItem(title: "Following", value: "\(viewModel.followingList.count)")
            }
            .buttonStyle(PlainButtonStyle())
            
            statItem(title: "Clout", value: viewModel.formatClout(user.clout))
        }
        .padding(.horizontal, 20)
    }
    
    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtonsRow(user: BasicUserInfo) -> some View {
        HStack(spacing: 12) {
            if viewModel.isOwnProfile {
                Button(action: { showingEditProfile = true }) {
                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
                
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
            } else {
                Button(action: {
                    Task { await viewModel.toggleFollow() }
                }) {
                    Text(viewModel.isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.isFollowing ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(viewModel.isFollowing ? Color.white : Color.cyan)
                        .cornerRadius(8)
                }
                
                Button(action: { /* Future implementation */ }) {
                    Text("Message")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Tab Bar Section
    
    private var tabBarSection: some View {
        HStack(spacing: 0) {
            ForEach(0..<viewModel.tabTitles.count, id: \.self) { index in
                tabBarItem(index: index)
            }
        }
        .background(Color.black)
        .padding(.top, 20)
    }
    
    private func tabBarItem(index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.selectedTab = index
            }
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.tabIcons[index])
                        .font(.caption)
                        .foregroundColor(viewModel.selectedTab == index ?
                            .cyan.opacity(0.8) : .gray.opacity(0.6))
                    
                    Text(viewModel.tabTitles[index])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.selectedTab == index ? .cyan : .gray)
                    
                    Text("(\(viewModel.getTabCount(for: index)))")
                        .font(.system(size: 10))
                        .foregroundColor(viewModel.selectedTab == index ?
                            .cyan.opacity(0.8) : .gray.opacity(0.6))
                }
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(viewModel.selectedTab == index ? Color.cyan : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Video Grid Section (FIXED WITH THUMBNAILS)
    
    private var videoGridSection: some View {
        Group {
            if viewModel.isLoadingVideos {
                loadingVideosView
            } else if viewModel.filteredVideos(for: viewModel.selectedTab).isEmpty {
                emptyVideosView
            } else {
                videoGrid
            }
        }
        .id(viewModel.selectedTab)
    }
    
    private var videoGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
            spacing: 1
        ) {
            ForEach(Array(viewModel.filteredVideos(for: viewModel.selectedTab).enumerated()), id: \.element.id) { index, video in
                videoGridItem(video: video, index: index)
            }
        }
        .padding(.horizontal, 0)
        .padding(.bottom, 100)
    }
    
    // MARK: - FIXED Video Grid Item (Using VideoThumbnailView)
    
    private func videoGridItem(video: CoreVideoMetadata, index: Int) -> some View {
        VideoThumbnailView(
            video: video,
            showEngagementBadge: true
        ) {
            openVideo(video: video, index: index)
        }
        .contextMenu {
            videoContextMenu(video: video)
        }
        .overlay {
            if isDeletingVideo && videoToDelete?.id == video.id {
                Color.black.opacity(0.7)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    )
            }
        }
    }
    
    private func videoContextMenu(video: CoreVideoMetadata) -> some View {
        Group {
            if viewModel.isOwnProfile {
                Button("Delete Video", role: .destructive) {
                    videoToDelete = video
                    showingDeleteConfirmation = true
                }
                Button("Share") { shareVideo(video) }
            } else {
                Button("Share") { shareVideo(video) }
            }
        }
    }
    
    private func handleGridEngagement(_ interactionType: InteractionType, video: CoreVideoMetadata) {
        Task { @MainActor in
            switch interactionType {
            case .hype:
                print("Hype video: \(video.title)")
                triggerHapticFeedback(.light)
            case .reply:
                openVideoReplies(video)
            case .share:
                shareVideo(video)
            case .cool:
                print("Cool video: \(video.title)")
                triggerHapticFeedback(.soft)
            case .view:
                print("View engagement for video: \(video.title)")
            }
        }
    }
    
    private func performVideoDelete() async {
        guard let video = videoToDelete else { return }
        isDeletingVideo = true
        
        let success = await viewModel.deleteVideo(video)
        if success {
            print("Video deleted successfully: \(video.title)")
            triggerHapticFeedback(.medium)
        }
        
        isDeletingVideo = false
        videoToDelete = nil
    }
    
    private func openVideoReplies(_ video: CoreVideoMetadata) {
        print("Opening replies for video: \(video.title)")
    }
    
    private func shareVideo(_ video: CoreVideoMetadata) {
        print("Sharing video: \(video.title)")
    }
    
    private func openVideo(video: CoreVideoMetadata, index: Int) {
        selectedVideo = video
        selectedVideoIndex = index
        showingVideoPlayer = true
    }
    
    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
    
    private func preloadAdjacentVideos() {
        let videos = viewModel.filteredVideos(for: viewModel.selectedTab)
        let preloadIndices = [
            selectedVideoIndex - 1,
            selectedVideoIndex + 1
        ].filter { $0 >= 0 && $0 < videos.count }
        
        // Preload thumbnails for adjacent videos
        for index in preloadIndices {
            let video = videos[index]
            Task {
                // Generate thumbnail in background for smooth grid return
                if ThumbnailCacheManager.shared.getCachedThumbnail(for: video.id) == nil {
                    print("PROFILE: Preloading thumbnail for video \(index)")
                }
            }
        }
    }
    
    // MARK: - Hype Rating Calculation
    
    private func calculateHypeRating(user: BasicUserInfo) -> Double {
        let hypeRating = HypeRating(
            userID: user.id,
            baseRating: tierBaseRating(for: user.tier),
            startingBonus: getUserStartingBonus(for: user)
        )
        
        let userVideos = viewModel.userVideos
        let engagementScore: Double = {
            guard !userVideos.isEmpty else { return 0.0 }
            
            let totalHypes = userVideos.reduce(0) { $0 + $1.hypeCount }
            let totalCools = userVideos.reduce(0) { $0 + $1.coolCount }
            let totalViews = userVideos.reduce(0) { $0 + $1.viewCount }
            let totalReplies = userVideos.reduce(0) { $0 + $1.replyCount }
            
            let totalReactions = totalHypes + totalCools
            let engagementRatio = totalReactions > 0 ? Double(totalHypes) / Double(totalReactions) : 0.5
            let engagementPoints = engagementRatio * Double(InteractionType.hype.pointValue) * 1.5
            
            let viewEngagementRatio = totalViews > 0 ? Double(totalReactions) / Double(totalViews) : 0.0
            let viewPoints = min(10.0, viewEngagementRatio * 1000.0)
            
            let maxThreadChildren = Double(OptimizationConfig.Threading.maxChildrenPerThread)
            let replyBonus = min(5.0, Double(totalReplies) / maxThreadChildren * 5.0)
            
            return engagementPoints + viewPoints + replyBonus
        }()
        
        let activityScore: Double = {
            let recentVideos = userVideos.filter {
                Date().timeIntervalSince($0.createdAt) < OptimizationConfig.Threading.trendingWindowHours * 3600
            }
            return min(15.0, Double(recentVideos.count) * 2.5)
        }()
        
        let cloutBaseline = Double(OptimizationConfig.User.defaultStartingClout)
        let cloutBonus = min(10.0, Double(user.clout) / cloutBaseline * 10.0)
        
        let followerThreshold = Double(OptimizationConfig.Performance.maxBackgroundTasks)
        let socialBonus = min(8.0, Double(viewModel.followersList.count) / followerThreshold * 8.0)
        
        let verificationBonus: Double = user.isVerified ? 5.0 : 0.0
        
        let baseRating = hypeRating.effectiveRating
        let bonusPoints = engagementScore + activityScore + cloutBonus + socialBonus + verificationBonus
        let finalRating = (baseRating / 100.0 * 50.0) + bonusPoints
        
        let clampedRating = min(100.0, max(0.0, finalRating))
        
        print("🔥 HYPE METER: \(user.username) = \(Int(clampedRating))%")
        
        return clampedRating
    }
    
    // MARK: - Helper Functions
    
    private func shouldShowBio(user: BasicUserInfo) -> Bool {
        return getBioForUser(user) != nil || viewModel.isOwnProfile
    }
    
    private func getBioForUser(_ user: BasicUserInfo) -> String? {
        if let bio = viewModel.getBioForUser(user) {
            return bio
        }
        
        if user.isVerified {
            return generateContextualBio(for: user)
        }
        
        if user.tier.isFounderTier {
            return generateSampleBio(for: user)
        }
        
        return nil
    }
    
    private func generateContextualBio(for user: BasicUserInfo) -> String? {
        let videoCount = viewModel.userVideos.count
        let followerCount = viewModel.followersList.count
        let clout = user.clout
        
        var bioComponents: [String] = []
        
        if clout > OptimizationConfig.User.defaultStartingClout * 5 {
            bioComponents.append("🌟 High performer")
        }
        
        if videoCount >= OptimizationConfig.Threading.maxChildrenPerThread {
            bioComponents.append("📹 Active creator")
        }
        
        if followerCount >= 100 {
            bioComponents.append("👥 Community leader")
        }
        
        if user.tier != .rookie {
            bioComponents.append("🚀 \(user.tier.displayName)")
        }
        
        if user.isVerified {
            bioComponents.append("✅ Verified")
        }
        
        let bio = bioComponents.joined(separator: " | ")
        return bio.count <= OptimizationConfig.User.maxBioLength ? bio : nil
    }
    
    private func generateSampleBio(for user: BasicUserInfo) -> String? {
        switch user.tier {
        case .founder:
            return "Building the future of social video 🚀 | Creator of Stitch Social"
        case .coFounder:
            return "Co-founder at Stitch Social | Passionate about connecting creators 🎬"
        case .topCreator:
            return "Top creator with \(viewModel.formatClout(user.clout)) clout | Making viral content daily ✨"
        case .partner:
            return "Official partner creator | \(viewModel.userVideos.count) threads and counting 🔥"
        default:
            return nil
        }
    }
    
    private func tierBaseRating(for tier: UserTier) -> Double {
        let baseClout = Double(OptimizationConfig.User.defaultStartingClout)
        
        switch tier {
        case .founder, .coFounder: return baseClout * 0.063
        case .topCreator: return baseClout * 0.057
        case .partner: return baseClout * 0.050
        case .influencer: return baseClout * 0.043
        case .rising: return baseClout * 0.033
        case .rookie: return baseClout * 0.023
        default: return baseClout * 0.017
        }
    }
    
    private func getUserStartingBonus(for user: BasicUserInfo) -> UserStartingBonus {
        if user.isVerified {
            return .betaTester
        } else if user.tier.isFounderTier {
            return .earlyAdopter
        } else {
            return .newcomer
        }
    }
    
    private func getTierColors(_ tier: UserTier) -> [Color] {
        switch tier {
        case .founder, .coFounder: return [.yellow, .orange]
        case .topCreator: return [.blue, .purple]
        case .partner: return [.green, .mint]
        case .influencer: return [.pink, .purple]
        case .rising: return [.cyan, .blue]
        case .rookie: return [.gray, .white]
        default: return [.gray, .white]
        }
    }
    
    private func getTierIcon(_ tier: UserTier) -> String {
        switch tier {
        case .founder, .coFounder: return "crown.fill"
        case .topCreator: return "star.fill"
        case .partner: return "handshake.fill"
        case .influencer: return "megaphone.fill"
        case .rising: return "arrow.up.circle.fill"
        case .rookie: return "person.circle.fill"
        default: return "person.circle"
        }
    }
    
    // MARK: - Helper Views
    
    private var scrollTracker: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self,
                           value: geometry.frame(in: .named("scroll")).minY)
        }
    }
    
    private func handleScrollChange(_ offset: CGFloat) {
        let shouldShow = -offset > 300
        withAnimation(.easeInOut(duration: 0.2)) {
            showStickyTabBar = shouldShow
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Loading Profile...")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text("Error")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(error)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel.loadProfile() }
            }
            .font(.headline)
            .foregroundColor(.black)
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    private var noUserView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No User Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private var loadingVideosView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
            Text("Loading Videos...")
                .foregroundColor(.gray)
        }
        .frame(height: 200)
    }
    
    private var emptyVideosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("No \(viewModel.tabTitles[viewModel.selectedTab])")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(height: 400)
    }
    
    private var stickyTabBar: some View {
        VStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 44)
            tabBarSection
                .background(Color.black.opacity(0.9))
                .background(.ultraThinMaterial)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - ENHANCED Full Screen Video Player
    
    private var fullScreenVideoPlayer: some View {
        Group {
            if selectedVideoIndex < viewModel.filteredVideos(for: viewModel.selectedTab).count {
                let video = viewModel.filteredVideos(for: viewModel.selectedTab)[selectedVideoIndex]
                
                VideoPlayerView(
                    video: video,
                    isActive: true,
                    onEngagement: { interactionType in
                        handleGridEngagement(interactionType, video: video)
                    }
                )
                .background(Color.black)
                .onTapGesture {
                    showingVideoPlayer = false
                }
                .onAppear {
                    // Preload adjacent videos for smooth swiping
                    preloadAdjacentVideos()
                }
            }
        }
    }
    
    // MARK: - Sheet Views
    
    private var followingSheet: some View {
        NavigationView {
            UserListView(
                title: "Following",
                users: viewModel.followingList,
                isLoading: viewModel.isLoadingFollowing
            )
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowingList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadFollowing() }
        }
    }

    private var followersSheet: some View {
        NavigationView {
            UserListView(
                title: "Followers",
                users: viewModel.followersList,
                isLoading: viewModel.isLoadingFollowers
            )
            .navigationTitle("Followers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingFollowersList = false }
                        .foregroundColor(.cyan)
                }
            }
        }
        .onAppear {
            Task { await viewModel.loadFollowers() }
        }
    }

    private var settingsSheet: some View {
        SettingsView()
            .environmentObject(viewModel.authService)
    }

    private var editProfileSheet: some View {
        Group {
            if let user = viewModel.currentUser {
                EditProfileView(
                    userService: userService,
                    user: Binding(
                        get: { user },
                        set: { newUser in
                            // Update the viewModel's currentUser when EditProfileView updates it
                            Task {
                                await viewModel.refreshProfile()
                            }
                        }
                    )
                )
            } else {
                // Simple fallback without NavigationView to avoid toolbar conflicts
                VStack(spacing: 20) {
                    Text("Profile not loaded")
                        .foregroundColor(.gray)
                    
                    Button("Retry") {
                        Task { await viewModel.loadProfile() }
                    }
                    .foregroundColor(.cyan)
                    
                    Button("Cancel") {
                        showingEditProfile = false
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 20)
                }
                .padding()
                .background(Color.black.ignoresSafeArea())
            }
        }
    }
}

// MARK: - Supporting Components

struct UserListView: View {
    let title: String
    let users: [BasicUserInfo]
    let isLoading: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else if users.isEmpty {
                VStack {
                    Text("No \(title)")
                        .foregroundColor(.white)
                }
            } else {
                ScrollView {
                    LazyVStack {
                        ForEach(users, id: \.id) { user in
                            UserRowView(user: user)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct UserRowView: View {
    let user: BasicUserInfo
    
    var body: some View {
        HStack {
            AsyncImage(url: URL(string: user.profileImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            VStack(alignment: .leading) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
