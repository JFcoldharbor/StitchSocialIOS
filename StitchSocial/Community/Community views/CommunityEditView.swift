//
//  CommunityEditView.swift
//  StitchSocial
//
//  Layer 8: Views - Creator Community Edit & Mod Tools
//  Dependencies: CommunityService, CommunityTypes, FirebaseStorage
//  Features: Edit name/desc/image, manage moderators, ban/unban, member list
//
//  CACHING: Uses CommunityService cached membership data (10-min TTL).
//  Member list is fetched once per session, not per tab switch.
//  Profile image upload goes to Storage, only URL stored in Firestore (1 write).
//

import SwiftUI
import PhotosUI
import FirebaseStorage

struct CommunityEditView: View {
    
    // MARK: - Properties
    
    let creatorID: String
    let community: Community
    
    @ObservedObject private var communityService = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: CommunityEditTab = .settings
    @State private var communityName: String
    @State private var communityDescription: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var isUploadingImage = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingSaveSuccess = false
    
    // Mod tools state
    @State private var members: [CommunityMembership] = []
    @State private var isLoadingMembers = false
    @State private var searchText = ""
    @State private var memberFilter: MemberFilter = .all
    @State private var selectedMember: CommunityMembership?
    @State private var showingMemberActions = false
    @State private var showingBanConfirm = false
    @State private var showingUnbanConfirm = false
    @State private var showingModConfirm = false
    @State private var showingRemoveModConfirm = false
    
    init(creatorID: String, community: Community) {
        self.creatorID = creatorID
        self.community = community
        _communityName = State(initialValue: community.displayName)
        _communityDescription = State(initialValue: community.description)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    tabPicker
                    
                    switch selectedTab {
                    case .settings:
                        settingsContent
                    case .moderators:
                        moderatorsContent
                    case .members:
                        membersContent
                    }
                }
            }
            .navigationTitle("Edit Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == .settings {
                        Button("Save") { Task { await saveChanges() } }
                            .foregroundColor(.cyan)
                            .fontWeight(.semibold)
                            .disabled(isSaving)
                    }
                }
            }
        }
        .task {
            await loadMembers()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(CommunityEditTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .cyan : .white.opacity(0.5))
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Settings Content
    
    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileImageSection
                nameDescriptionSection
                statsCard
                
                if showingSaveSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Changes saved")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .transition(.opacity)
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Profile Image Section
    
    private var profileImageSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Current or selected image
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                } else if let url = community.profileImageURL, let imageURL = URL(string: url) {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            defaultAvatar
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    defaultAvatar
                }
                
                // Upload overlay
                if isUploadingImage {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 100, height: 100)
                        .overlay(ProgressView().tint(.white))
                }
                
                // Camera badge
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.cyan)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .offset(x: 38, y: 38)
                .disabled(isUploadingImage)
            }
            
            Text("Tap camera to change")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
        }
    }
    
    private var defaultAvatar: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [.cyan, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 100, height: 100)
            .overlay(
                Text(String(community.creatorDisplayName.prefix(2)).uppercased())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Name & Description
    
    private var nameDescriptionSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Community Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                
                TextField("", text: $communityName, prompt: Text("Community name").foregroundColor(.white.opacity(0.25)))
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text("\(communityDescription.count)/300")
                        .font(.system(size: 11))
                        .foregroundColor(communityDescription.count > 300 ? .red : .white.opacity(0.3))
                }
                
                TextField("", text: $communityDescription, prompt: Text("What's your community about?").foregroundColor(.white.opacity(0.25)), axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineLimit(3...6)
                    .padding(14)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        HStack(spacing: 0) {
            statBlock(value: "\(community.memberCount)", label: "Members")
            divider
            statBlock(value: "\(community.totalPosts)", label: "Posts")
            divider
            statBlock(value: "\(moderators.count)", label: "Mods")
        }
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 30)
    }
    
    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Moderators Content
    
    private var moderatorsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Current mods
                if moderators.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shield")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No Moderators Yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Promote members from the Members tab. They need Level 100+.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                } else {
                    ForEach(moderators) { mod in
                        memberRow(mod, showModBadge: true)
                    }
                }
                
                // Eligible members (Lv100+ not yet mod)
                let eligible = members.filter { $0.canBeNominatedMod && !$0.isModerator && !$0.isBanned }
                if !eligible.isEmpty {
                    sectionHeader("ELIGIBLE FOR MOD (LV 100+)")
                    ForEach(eligible) { member in
                        memberRow(member, showModBadge: false)
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Members Content
    
    private var membersContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.4))
                TextField("Search members", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .padding(12)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MemberFilter.allCases, id: \.self) { filter in
                        Button {
                            memberFilter = filter
                        } label: {
                            Text(filter.title)
                                .font(.system(size: 12, weight: memberFilter == filter ? .bold : .medium))
                                .foregroundColor(memberFilter == filter ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(memberFilter == filter ? Color.cyan : Color.white.opacity(0.06))
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 10)
            
            // Member list
            if isLoadingMembers {
                Spacer()
                ProgressView().tint(.cyan)
                Spacer()
            } else if filteredMembers.isEmpty {
                Spacer()
                Text("No members found")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredMembers) { member in
                            memberRow(member, showModBadge: member.isModerator)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Member Row
    
    private func memberRow(_ member: CommunityMembership, showModBadge: Bool) -> some View {
        Button {
            selectedMember = member
            showingMemberActions = true
        } label: {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: member.isModerator ? [.yellow, .orange] : [.cyan, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(member.username.prefix(2)).uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("@\(member.username)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        if showModBadge {
                            Text("MOD")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        if member.isBanned {
                            Text("BANNED")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Text("Lv \(member.level)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                        
                        Text("\(member.totalPosts) posts")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("Joined \(timeAgo(member.joinedAt))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                
                Spacer()
                
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(member.isBanned ? Color.red.opacity(0.06) : Color.white.opacity(0.06))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog(
            "@\(selectedMember?.username ?? "")",
            isPresented: $showingMemberActions,
            titleVisibility: .visible
        ) {
            if let m = selectedMember {
                if !m.isModerator && m.canBeNominatedMod && !m.isBanned {
                    Button("Make Moderator") { showingModConfirm = true }
                }
                if m.isModerator {
                    Button("Remove Moderator", role: .destructive) { showingRemoveModConfirm = true }
                }
                if !m.isBanned {
                    Button("Ban Member", role: .destructive) { showingBanConfirm = true }
                } else {
                    Button("Unban Member") { showingUnbanConfirm = true }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .alert("Make Moderator?", isPresented: $showingModConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm") { Task { await toggleMod(true) } }
        } message: {
            Text("@\(selectedMember?.username ?? "") will be able to delete posts and mute members.")
        }
        .alert("Remove Moderator?", isPresented: $showingRemoveModConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { Task { await toggleMod(false) } }
        }
        .alert("Ban Member?", isPresented: $showingBanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Ban", role: .destructive) { Task { await banMember() } }
        } message: {
            Text("@\(selectedMember?.username ?? "") won't be able to post or interact in your community.")
        }
        .alert("Unban Member?", isPresented: $showingUnbanConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Unban") { Task { await unbanMember() } }
        }
    }
    
    // MARK: - Helpers
    
    private var moderators: [CommunityMembership] {
        members.filter { $0.isModerator }
    }
    
    private var filteredMembers: [CommunityMembership] {
        var result = members
        
        switch memberFilter {
        case .all: break
        case .moderators: result = result.filter { $0.isModerator }
        case .banned: result = result.filter { $0.isBanned }
        case .topLevel: result = result.sorted { $0.level > $1.level }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundColor(.white.opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 30 { return "\(days)d ago" }
        if days < 365 { return "\(days / 30)mo ago" }
        return "\(days / 365)y ago"
    }
    
    // MARK: - Actions
    
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        
        await MainActor.run { profileImage = image }
    }
    
    private func uploadProfileImage() async throws -> String? {
        guard let image = profileImage,
              let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        
        isUploadingImage = true
        defer { Task { @MainActor in isUploadingImage = false } }
        
        let path = "communities/\(creatorID)/profile.jpg"
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }
    
    private func saveChanges() async {
        isSaving = true
        defer { Task { @MainActor in isSaving = false } }
        
        do {
            // Upload image if changed (1 Storage write + 1 Firestore write)
            var imageURL: String? = nil
            if profileImage != nil {
                imageURL = try await uploadProfileImage()
            }
            
            try await communityService.updateCommunity(
                creatorID: creatorID,
                displayName: communityName.trimmingCharacters(in: .whitespaces),
                description: communityDescription.trimmingCharacters(in: .whitespaces),
                profileImageURL: imageURL
            )
            
            await MainActor.run {
                showingSaveSuccess = true
                // Auto-hide after 2 sec
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingSaveSuccess = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func loadMembers() async {
        isLoadingMembers = true
        do {
            // Single fetch, cached for session — no per-tab refetch
            let result = try await communityService.fetchMembers(creatorID: creatorID, limit: 100)
            await MainActor.run { members = result.members }
        } catch {
            print("⚠️ COMMUNITY EDIT: Failed to load members - \(error.localizedDescription)")
        }
        await MainActor.run { isLoadingMembers = false }
    }
    
    private func toggleMod(_ isMod: Bool) async {
        guard let member = selectedMember else { return }
        do {
            try await communityService.setModerator(userID: member.userID, creatorID: creatorID, isMod: isMod)
            await loadMembers()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func banMember() async {
        guard let member = selectedMember else { return }
        do {
            try await communityService.banMember(userID: member.userID, creatorID: creatorID)
            await loadMembers()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func unbanMember() async {
        guard let member = selectedMember else { return }
        do {
            try await communityService.unbanMember(userID: member.userID, creatorID: creatorID)
            await loadMembers()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Edit Tab

enum CommunityEditTab: String, CaseIterable {
    case settings, moderators, members
    
    var title: String {
        switch self {
        case .settings: return "Settings"
        case .moderators: return "Moderators"
        case .members: return "Members"
        }
    }
    
    var icon: String {
        switch self {
        case .settings: return "gearshape.fill"
        case .moderators: return "shield.fill"
        case .members: return "person.2.fill"
        }
    }
}

// MARK: - Member Filter

enum MemberFilter: String, CaseIterable {
    case all, moderators, banned, topLevel
    
    var title: String {
        switch self {
        case .all: return "All"
        case .moderators: return "Mods"
        case .banned: return "Banned"
        case .topLevel: return "Top Level"
        }
    }
}
