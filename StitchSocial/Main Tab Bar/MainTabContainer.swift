//
//  MainTabContainer.swift
//  StitchSocial
//
//  Layer 8: Views - Main Tab Navigation with Service Injection + PRELOADING
//  Dependencies: Layer 4 (Services), Layer 6 (NavigationCoordinator), Layer 1 (Foundation)
//  Central navigation container with custom dipped tab bar
//  FIXED: Uses VideoPreloadingService.shared singleton
//

import SwiftUI
import FirebaseAuth

struct MainTabContainer: View {
    
    // MARK: - Services (Centralized)
    
    @StateObject private var authService = AuthService()
    @StateObject private var userService = UserService()
    @StateObject private var videoService = VideoService()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    
    // MARK: - Preloading Service (FIXED: Use singleton via ObservedObject)
    
    @ObservedObject private var videoPreloadingService = VideoPreloadingService.shared
    
    // MARK: - Navigation State
    
    @State private var selectedTab: MainAppTab = .discovery
    @State private var showingRecording = false
    
    // MARK: - Double Upload Prevention
    @State private var isProcessingVideoCreation = false
    
    // MARK: - Tab Preloading State
    @State private var hasPreloadedHome = false
    
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
                        handleTabSelection(tab)
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
                    guard !isProcessingVideoCreation else {
                        print("MAIN TAB: Video creation already processing, ignoring duplicate call")
                        return
                    }
                    
                    isProcessingVideoCreation = true
                    
                    print("MAIN TAB: Video upload completed - \(videoMetadata.title)")
                    print("MAIN TAB: Profile update handled by VideoCoordinator, not duplicating")
                    
                    showingRecording = false
                    
                    NotificationCenter.default.post(
                        name: .refreshFeeds,
                        object: nil,
                        userInfo: ["newVideoID": videoMetadata.id]
                    )
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isProcessingVideoCreation = false
                    }
                },
                onCancel: {
                    showingRecording = false
                    isProcessingVideoCreation = false
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
            selectedTab = newTab
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            handleTabChange(from: oldTab, to: newTab)
        }
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            HomeFeedView()
            
        case .discovery:
            DiscoveryView()
            
        case .progression:
            ProfileView(
                authService: authService,
                userService: userService,
                videoService: videoService
            )
            
        case .notifications:
            NotificationView()
        }
    }
    
    // MARK: - INSTAGRAM/TIKTOK PRELOADING PATTERN
    
    private func handleTabSelection(_ tab: MainAppTab) {
        print("🏷️ TAB SWITCH: From \(selectedTab.title) to \(tab.title)")
        selectedTab = tab
        navigationCoordinator.selectTab(tab)
    }
    
    private func handleTabChange(from oldTab: MainAppTab, to newTab: MainAppTab) {
        print("🎬 TAB CHANGED: \(oldTab.title) → \(newTab.title)")
        
        // Trigger preload for destination tab BEFORE user arrives
        switch newTab {
        case .home:
            if !hasPreloadedHome {
                print("🎬 PRELOAD TRIGGER: HomeFeed first load")
                hasPreloadedHome = true
                // HomeFeed will preload on its own .onAppear
            } else {
                print("🎬 PRELOAD TRIGGER: HomeFeed return - triggering preload")
                // Post notification to trigger HomeFeed preload
                NotificationCenter.default.post(
                    name: .preloadHomeFeed,
                    object: nil
                )
            }
            
        case .discovery:
            print("🎬 PRELOAD TRIGGER: Discovery (handles own preloading)")
            // Discovery already preloads on appear
            
        case .progression:
            print("🎬 PRELOAD TRIGGER: Profile (handles own preloading)")
            // Profile uses VideoPreloadingService for grid videos
            
        case .notifications:
            print("🎬 PRELOAD TRIGGER: Notifications (no video preload needed)")
            break
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let refreshFeeds = Notification.Name("refreshFeeds")
    static let preloadHomeFeed = Notification.Name("preloadHomeFeed")
}

// MARK: - Preview

#Preview {
    MainTabContainer()
}
