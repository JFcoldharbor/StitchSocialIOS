//
//  MainTabContainer.swift
//  CleanBeta
//
//  Layer 8: Views - Main Tab Navigation with Service Injection
//  Dependencies: Layer 4 (Services), Layer 1 (Foundation)
//  Central navigation container with custom dipped tab bar
//  FIXED: Added VideoService for ProfileView initialization
//

import SwiftUI
import FirebaseAuth

struct MainTabContainer: View {
    
    // MARK: - Services (Centralized)
    
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    
    // MARK: - Navigation State
    
    @State private var selectedTab: MainAppTab = .home
    @State private var showingRecording = false
    
    var body: some View {
        ZStack {
            // Background
            StitchColors.background.ignoresSafeArea()
            
            // Tab Content
            tabContent
            
            // Custom Dipped Tab Bar
            VStack {
                Spacer()
                
                CustomDippedTabBar(
                    selectedTab: $selectedTab,
                    onTabSelected: { tab in
                        selectedTab = tab
                    },
                    onCreateTapped: {
                        showingRecording = true
                    }
                )
                .padding(.bottom, 12) // Move tab bar down 15%
            }
        }
        .environmentObject(authService)
        .environmentObject(userService)
        .environmentObject(videoService)
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView(
                recordingContext: RecordingContext.newThread,
                onVideoCreated: { videoMetadata in
                    // Handle video creation completion
                    print("Video created: \(videoMetadata.title)")
                    showingRecording = false
                },
                onCancel: {
                    // Handle recording cancellation
                    showingRecording = false
                }
            )
        }
        .task {
            try? await authService.initialize()
        }
    }
    
    // MARK: - Tab Content (FIXED)
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeFeedView()
            
        case .discovery:
            DiscoveryView()
            
        case .progression:
            // FIXED: Pass all required services to ProfileView
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService
            )
            
        case .notifications:
            NotificationView()
        }
    }
}

// MARK: - Preview (Updated)

#Preview {
    MainTabContainer()
}
