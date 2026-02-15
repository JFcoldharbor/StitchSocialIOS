//
//  CreatorCommunitySettingsView.swift
//  StitchSocial
//
//  Layer 8: Views - Creator Community Settings
//  Dependencies: CommunityService, CommunityTypes, UserTier
//  Features: Activate/deactivate community, set name/description, view stats
//

import SwiftUI

struct CreatorCommunitySettingsView: View {
    
    // MARK: - Properties
    
    let creatorID: String
    let creatorUsername: String
    let creatorDisplayName: String
    let creatorTier: UserTier
    
    @ObservedObject private var communityService = CommunityService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var status: CommunityStatus = .notCreated
    @State private var communityName = ""
    @State private var communityDescription = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingDeactivateConfirm = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            statusCard
                            
                            switch status {
                            case .notCreated:
                                notCreatedView
                            case .inactive:
                                inactiveView
                            case .active(let community):
                                activeView(community)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        .task {
            await loadStatus()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .alert("Deactivate Community?", isPresented: $showingDeactivateConfirm) {
            Button("Keep Active", role: .cancel) { }
            Button("Deactivate", role: .destructive) {
                Task { await deactivate() }
            }
        } message: {
            Text("Members won't be removed but they can't see or interact with the community until you reactivate.")
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(statusSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Text(statusBadge)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
    }
    
    private var statusColor: Color {
        switch status {
        case .notCreated: return .gray
        case .inactive: return .yellow
        case .active: return .green
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .notCreated: return "bubble.left.and.bubble.right"
        case .inactive: return "pause.circle.fill"
        case .active: return "checkmark.circle.fill"
        }
    }
    
    private var statusTitle: String {
        switch status {
        case .notCreated: return "No Community Yet"
        case .inactive: return "Community Ready"
        case .active: return "Community Active"
        }
    }
    
    private var statusSubtitle: String {
        switch status {
        case .notCreated:
            return Community.canCreateCommunity(tier: creatorTier)
                ? "You're eligible! Create your community below."
                : "Reach Influencer tier to unlock."
        case .inactive:
            return "Auto-created when you reached \(creatorTier.displayName). Activate to go live."
        case .active(let c):
            return "\(c.memberCount) members"
        }
    }
    
    private var statusBadge: String {
        switch status {
        case .notCreated: return "LOCKED"
        case .inactive: return "INACTIVE"
        case .active: return "LIVE"
        }
    }
    
    // MARK: - Not Created View
    
    private var notCreatedView: some View {
        VStack(spacing: 16) {
            if Community.canCreateCommunity(tier: creatorTier) {
                nameDescriptionFields
                
                Button {
                    Task { await createAndActivate() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Community")
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan)
                    .cornerRadius(14)
                }
                .disabled(isSaving || communityName.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                tierRequirementCard
            }
        }
    }
    
    // MARK: - Inactive View
    
    private var inactiveView: some View {
        VStack(spacing: 16) {
            nameDescriptionFields
            
            Button {
                Task { await activate() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "bolt.circle.fill")
                        Text("Activate Community")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .disabled(isSaving)
            
            infoCard(
                icon: "info.circle.fill",
                text: "When you activate, your subscribers can join and start earning XP, unlocking badges, and engaging with your content."
            )
        }
    }
    
    @State private var showingEditView = false
    
    // MARK: - Active View
    
    private func activeView(_ community: Community) -> some View {
        VStack(spacing: 16) {
            // Stats
            HStack(spacing: 0) {
                statBlock(value: "\(community.memberCount)", label: "Members")
                statBlock(value: "\(community.totalPosts)", label: "Posts")
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)
            
            // Edit Community (full editor with image + mod tools)
            Button {
                showingEditView = true
            } label: {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                    Text("Edit Community & Mod Tools")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cyan)
                .cornerRadius(14)
            }
            .sheet(isPresented: $showingEditView) {
                CommunityEditView(creatorID: creatorID, community: community)
            }
            
            // Deactivate
            Button {
                showingDeactivateConfirm = true
            } label: {
                Text("Deactivate Community")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Shared Components
    
    private var nameDescriptionFields: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Community Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                
                TextField("", text: $communityName, prompt: Text("e.g. The \(creatorDisplayName) Crew").foregroundColor(.white.opacity(0.25)))
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
                Text("Description")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                
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
    
    private var tierRequirementCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Reach Influencer Tier")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("Communities are available for creators at Influencer tier (100K+ followers) and above. Keep growing!")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 6) {
                Text("Current:")
                    .foregroundColor(.white.opacity(0.4))
                Text(creatorTier.displayName)
                    .foregroundColor(.cyan)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 13))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .cornerRadius(18)
    }
    
    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private func infoCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.cyan.opacity(0.7))
                .padding(.top, 2)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .lineSpacing(3)
        }
        .padding(14)
        .background(Color.cyan.opacity(0.06))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func loadStatus() async {
        isLoading = true
        do {
            status = try await communityService.fetchCommunityStatus(creatorID: creatorID)
            
            // Pre-fill fields if community exists
            if let community = status.community {
                communityName = community.displayName
                communityDescription = community.description
            } else {
                communityName = "\(creatorDisplayName)'s Community"
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isLoading = false
    }
    
    private func createAndActivate() async {
        isSaving = true
        do {
            let community = try await communityService.createCommunity(
                creatorID: creatorID,
                creatorUsername: creatorUsername,
                creatorDisplayName: creatorDisplayName,
                creatorTier: creatorTier,
                displayName: communityName.trimmingCharacters(in: .whitespaces),
                description: communityDescription.trimmingCharacters(in: .whitespaces)
            )
            status = .active(community)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isSaving = false
    }
    
    private func activate() async {
        isSaving = true
        do {
            let community = try await communityService.activateCommunity(
                creatorID: creatorID,
                displayName: communityName.trimmingCharacters(in: .whitespaces),
                description: communityDescription.trimmingCharacters(in: .whitespaces)
            )
            status = .active(community)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isSaving = false
    }
    
    private func saveChanges() async {
        isSaving = true
        do {
            try await communityService.updateCommunity(
                creatorID: creatorID,
                displayName: communityName.trimmingCharacters(in: .whitespaces),
                description: communityDescription.trimmingCharacters(in: .whitespaces)
            )
            // Refresh status
            status = try await communityService.fetchCommunityStatus(creatorID: creatorID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isSaving = false
    }
    
    private func deactivate() async {
        isSaving = true
        do {
            try await communityService.deactivateCommunity(creatorID: creatorID)
            status = try await communityService.fetchCommunityStatus(creatorID: creatorID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isSaving = false
    }
}
