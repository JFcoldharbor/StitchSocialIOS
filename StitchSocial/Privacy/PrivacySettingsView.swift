//
//  PrivacySettingsView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/17/26.
//


//
//  PrivacySettingsView.swift
//  StitchSocial
//
//  Layer 8: Views - Privacy Settings Screen
//  Dependencies: PrivacyService, PrivacySettings
//  Features: Account visibility, discoverability, default stitch visibility, age group
//
//  CACHING: Reads from PrivacyService.shared.currentPrivacy (already cached at login).
//  Only writes on user change — 1 Firestore write per toggle. No reads on open.
//

import SwiftUI

struct PrivacySettingsView: View {
    
    let userID: String
    
    @ObservedObject private var privacyService = PrivacyService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var settings: UserPrivacySettings = .default
    @State private var isLoaded = false
    @State private var isSaving = false
    @State private var showAgeConfirm = false
    @State private var pendingAgeGroup: AgeGroup?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        
                        // Account Visibility
                        privacySection(title: "ACCOUNT VISIBILITY", icon: "eye.fill", iconColor: .blue) {
                            privacyPicker(
                                label: "Who can see your profile",
                                selection: $settings.accountVisibility,
                                options: AccountVisibility.allCases,
                                labels: ["Public", "Followers Only"]
                            )
                        }
                        
                        // Discoverability
                        privacySection(title: "DISCOVERABILITY", icon: "magnifyingglass", iconColor: .cyan) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Show my stitches in Discovery")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Picker("", selection: $settings.discoverabilityMode) {
                                    Text("Everyone").tag(DiscoverabilityMode.public)
                                    Text("Followers").tag(DiscoverabilityMode.followers)
                                    Text("Nobody").tag(DiscoverabilityMode.none)
                                }
                                .pickerStyle(.segmented)
                                
                                Text(discoverabilityDescription)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // Default Stitch Visibility
                        privacySection(title: "DEFAULT STITCH VISIBILITY", icon: "video.fill", iconColor: .purple) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New stitches default to")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Picker("", selection: $settings.defaultStitchVisibility) {
                                    Label("Public", systemImage: "globe").tag(ContentVisibility.public)
                                    Label("Followers", systemImage: "person.2.fill").tag(ContentVisibility.followers)
                                    Label("Tagged", systemImage: "tag.fill").tag(ContentVisibility.tagged)
                                    Label("Private", systemImage: "lock.fill").tag(ContentVisibility.private)
                                }
                                .pickerStyle(.segmented)
                                
                                Text(visibilityDescription)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // Age Group
                        privacySection(title: "CONTENT SAFETY", icon: "shield.fill", iconColor: .green) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Age Group")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Picker("", selection: Binding(
                                    get: { settings.ageGroup },
                                    set: { newValue in
                                        if newValue != settings.ageGroup {
                                            pendingAgeGroup = newValue
                                            showAgeConfirm = true
                                        }
                                    }
                                )) {
                                    Text("Teen (Under 18)").tag(AgeGroup.teen)
                                    Text("Adult (18+)").tag(AgeGroup.adult)
                                }
                                .pickerStyle(.segmented)
                                
                                Text(ageGroupDescription)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                if settings.ageVerifiedAt != nil {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.shield.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.green)
                                        Text("Age verified")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                        
                        Spacer().frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
            .onChange(of: settings.accountVisibility) { _, _ in saveSettings() }
            .onChange(of: settings.discoverabilityMode) { _, _ in saveSettings() }
            .onChange(of: settings.defaultStitchVisibility) { _, _ in saveSettings() }
            .alert("Change Age Group?", isPresented: $showAgeConfirm) {
                Button("Confirm", role: .destructive) {
                    if let newAge = pendingAgeGroup {
                        settings.ageGroup = newAge
                        settings.ageVerifiedAt = Date()
                        saveSettings()
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingAgeGroup = nil
                }
            } message: {
                Text("This changes your content routing and cannot be easily reversed. Teen accounts see restricted content only.")
            }
            .onAppear {
                if !isLoaded {
                    settings = privacyService.currentPrivacy
                    isLoaded = true
                }
            }
        }
    }
    
    // MARK: - Save
    
    private func saveSettings() {
        guard !isSaving else { return }
        isSaving = true
        
        Task {
            do {
                try await privacyService.savePrivacySettings(userID: userID, settings: settings)
            } catch {
                print("⚠️ PRIVACY VIEW: Save failed: \(error)")
            }
            isSaving = false
        }
    }
    
    // MARK: - Descriptions
    
    private var discoverabilityDescription: String {
        switch settings.discoverabilityMode {
        case .public: return "Your stitches can appear in everyone's Discovery feed"
        case .followers: return "Only people who follow you will see your stitches"
        case .none: return "Your stitches won't appear in Discovery — only via your profile"
        }
    }
    
    private var visibilityDescription: String {
        switch settings.defaultStitchVisibility {
        case .public: return "Anyone can see your new stitches"
        case .followers: return "Only followers can view your new stitches"
        case .tagged: return "Only people you tag can view"
        case .private: return "Only you can see — saved as draft"
        }
    }
    
    private var ageGroupDescription: String {
        switch settings.ageGroup {
        case .teen: return "Content filtered for safety. Uploads go to the teen-safe bucket."
        case .adult: return "Full content access. Standard community guidelines apply."
        }
    }
    
    // MARK: - Components
    
    private func privacySection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(iconColor)
                
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
            
            content()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
        }
    }
    
    private func privacyPicker<T: Hashable>(
        label: String,
        selection: Binding<T>,
        options: [T],
        labels: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Picker("", selection: selection) {
                ForEach(Array(zip(options, labels)), id: \.0) { option, label in
                    Text(label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}