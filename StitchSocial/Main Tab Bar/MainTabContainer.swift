//
//  MainTabContainer.swift
//  StitchSocial
//
//  Layer 8: Views - Main Tab Navigation with Service Injection + PRELOADING
//  Dependencies: Layer 4 (Services), Layer 6 (NavigationCoordinator), Layer 1 (Foundation)
//  Central navigation container with custom dipped tab bar
//  PHASE 1 FIX: Removed duplicate Notification.Name declarations - now in NotificationNames.swift
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
            RecordingCoverView(
                isProcessingVideoCreation: $isProcessingVideoCreation,
                showingRecording: $showingRecording
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
                    // PHASE 1 FIX: Use unified notification
                    NotificationCenter.default.post(
                        name: .loadUserProfile,
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
                VideoPlayerComponent(video: video, isActive: true)
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
        #if DEBUG
        print("🏷️ TAB SWITCH: From \(selectedTab.title) to \(tab.title)")
        #endif
        selectedTab = tab
        navigationCoordinator.selectTab(tab)
    }
    
    private func handleTabChange(from oldTab: MainAppTab, to newTab: MainAppTab) {
        #if DEBUG
        print("🎬 TAB CHANGED: \(oldTab.title) → \(newTab.title)")
        #endif
        
        // Trigger preload for destination tab BEFORE user arrives
        switch newTab {
        case .home:
            if !hasPreloadedHome {
                #if DEBUG
                print("🎬 PRELOAD TRIGGER: HomeFeed first load")
                #endif
                hasPreloadedHome = true
                // HomeFeed will preload on its own .onAppear
            } else {
                #if DEBUG
                print("🎬 PRELOAD TRIGGER: HomeFeed return - triggering preload")
                #endif
                // PHASE 1 FIX: Use unified notification
                NotificationCenter.default.post(name: .preloadHomeFeed, object: nil)
            }
            
        case .discovery:
            #if DEBUG
            print("🎬 PRELOAD TRIGGER: Discovery (handles own preloading)")
            #endif
            // Discovery already preloads on appear
            
        case .progression:
            #if DEBUG
            print("🎬 PRELOAD TRIGGER: Profile (handles own preloading)")
            #endif
            // Profile uses VideoPreloadingService for grid videos
            
        case .notifications:
            #if DEBUG
            print("🎬 PRELOAD TRIGGER: Notifications (no video preload needed)")
            #endif
            break
        }
    }
}

// MARK: - REMOVED: Notification.Name extension
// Now in NotificationNames.swift - single source of truth

// MARK: - Stable Recording Cover
// Isolates RecordingView from MainTabContainer state changes.
// Without this, fullScreenCover recreates RecordingView every time
// the parent body re-evaluates (e.g. when gallery sheet dismisses),
// destroying the @StateObject RecordingController.

struct RecordingCoverView: View {
    @Binding var isProcessingVideoCreation: Bool
    @Binding var showingRecording: Bool
    @StateObject private var controller = RecordingController(recordingContext: .newThread)
    
    var body: some View {
        RecordingView(
            controller: controller,
            onVideoCreated: { videoMetadata in
                guard !isProcessingVideoCreation else {
                    #if DEBUG
                    print("MAIN TAB: Video creation already processing, ignoring duplicate call")
                    #endif
                    return
                }
                
                isProcessingVideoCreation = true
                
                #if DEBUG
                print("MAIN TAB: Video upload completed - \(videoMetadata.title)")
                #endif
                #if DEBUG
                print("MAIN TAB: Profile update handled by VideoCoordinator, not duplicating")
                #endif
                
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
}

// MARK: - Preview

#Preview {
    MainTabContainer()
}
