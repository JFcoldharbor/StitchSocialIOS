//
//  MainTabContainer.swift
//  CleanBeta
//
//  Layer 8: Views - Main Tab Navigation with Service Injection
//  Dependencies: Layer 4 (Services), Layer 6 (NavigationCoordinator), Layer 1 (Foundation)
//  Central navigation container with custom dipped tab bar
//  FIXED: Prevents double upload to profile by handling only UI state
//

import SwiftUI
import FirebaseAuth

struct MainTabContainer: View {
    
    // MARK: - Services (Centralized)
    
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    
    // MARK: - Navigation State
    
    @State private var selectedTab: MainAppTab = .home
    @State private var showingRecording = false
    
    // MARK: - Double Upload Prevention
    @State private var isProcessingVideoCreation = false
    
    var body: some View {
        ZStack {
            // Background
            StitchColors.background.ignoresSafeArea()
            
            // Tab Content
            tabContent
            
            // Custom Dipped Tab Bar - Fixed to extend to screen bottom
            VStack {
                Spacer()
                
                CustomDippedTabBar(
                    selectedTab: $selectedTab,
                    onTabSelected: { tab in
                        selectedTab = tab
                        navigationCoordinator.selectTab(tab)
                    },
                    onCreateTapped: {
                        showingRecording = true
                    }
                )
                .ignoresSafeArea(.all, edges: .bottom)
            }
        }
        .environmentObject(authService)
        .environmentObject(userService)
        .environmentObject(videoService)
        .environmentObject(navigationCoordinator)
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView(
                recordingContext: RecordingContext.newThread,
                onVideoCreated: { videoMetadata in
                    // FIXED: Prevent double processing and only handle UI state
                    guard !isProcessingVideoCreation else {
                        print("MAIN TAB: Video creation already processing, ignoring duplicate call")
                        return
                    }
                    
                    isProcessingVideoCreation = true
                    
                    // ONLY handle UI state - VideoCoordinator already updated the profile
                    print("MAIN TAB: Video upload completed - \(videoMetadata.title)")
                    print("MAIN TAB: Profile update handled by VideoCoordinator, not duplicating")
                    
                    // Close recording interface
                    showingRecording = false
                    
                    // Optional: Trigger UI refresh to show new video in feeds
                    // This does NOT update profile counts - just refreshes UI
                    NotificationCenter.default.post(
                        name: .refreshFeeds,
                        object: nil,
                        userInfo: ["newVideoID": videoMetadata.id]
                    )
                    
                    // Reset processing flag after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isProcessingVideoCreation = false
                    }
                },
                onCancel: {
                    // Handle recording cancellation
                    showingRecording = false
                    isProcessingVideoCreation = false // Reset flag on cancel
                }
            )
        }
        .sheet(isPresented: $navigationCoordinator.showingProfileSheet) {
            if let userID = navigationCoordinator.selectedUserID {
                ProfileView(
                    authService: authService,
                    userService: userService,
                    videoService: videoService
                )
                .onAppear {
                    // Load specific user profile
                    NotificationCenter.default.post(
                        name: NSNotification.Name("LoadUserProfile"),
                        object: nil,
                        userInfo: ["userID": userID]
                    )
                }
                .onDisappear {
                    navigationCoordinator.dismissProfileSheet()
                }
            }
        }
        .sheet(isPresented: $navigationCoordinator.showingSettingsSheet) {
            // TODO: Implement SettingsView when available
            Text("Settings Coming Soon")
                .font(.title)
                .padding()
                .onDisappear {
                    navigationCoordinator.dismissSettingsSheet()
                }
        }
        .fullScreenCover(isPresented: $navigationCoordinator.showingFullscreenVideo) {
            if let video = navigationCoordinator.fullscreenVideo {
                VideoPlayerView(video: video, isActive: true, onEngagement: nil)
                    .onDisappear {
                        navigationCoordinator.dismissVideo()
                    }
            }
        }
        .task {
            try? await authService.initialize()
            navigationCoordinator.setupNotificationObservers()
        }
        .onChange(of: navigationCoordinator.selectedTab) { oldTab, newTab in
            // Sync navigation coordinator tab changes with local state
            selectedTab = newTab
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

// MARK: - Notification Extensions

extension Notification.Name {
    static let refreshFeeds = Notification.Name("refreshFeeds")
}

// MARK: - Preview (Updated)

#Preview {
    MainTabContainer()
}
