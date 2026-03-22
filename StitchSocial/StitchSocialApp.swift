//
//  StitchSocialApp.swift
//  StitchSocial
//
//  UPDATED: Added Realtime Database presence tracking (optional)
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import FirebaseFunctions

@main
struct StitchSocialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Shared services for entire app
    @StateObject private var notificationService = NotificationService()
    @StateObject private var authService = AuthService()
    @StateObject private var muteManager = MuteContextManager.shared
    @StateObject private var backgroundUploadManager = BackgroundUploadManager.shared
    @StateObject private var versionGate = VersionGateService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Version gate — blocks the entire app if update required
                if versionGate.needsUpdate && versionGate.forceUpdate {
                    ForceUpdateView(versionGate: versionGate)
                } else {
                    ContentView()
                        .environmentObject(notificationService)
                        .environmentObject(authService)
                        .environmentObject(muteManager)
                    
                    // Upload progress pill — floats above all content
                    UploadProgressPill()
                    
                    // Toast notification overlay above all content
                    AppToastOverlay(notificationService: notificationService)
                        .allowsHitTesting(false)
                    
                    // Non-blocking update banner (when forceUpdate == false)
                    if versionGate.needsUpdate && !versionGate.forceUpdate {
                        VStack {
                            Spacer()
                            updateBanner
                        }
                        .transition(.move(edge: .bottom))
                    }
                }
            }
                .onChange(of: scenePhase) { _, phase in
                    handleScenePhaseChange(phase)
                }
                .onAppear {
                    // 🧪 DEBUG: Connect to Firebase Emulators for local testing
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATORS"] == "1" {
                        let settings = Firestore.firestore(database: "stitchfin").settings
                        settings.host = "localhost:8080"
                        settings.isSSLEnabled = false
                        settings.cacheSettings = MemoryCacheSettings()
                        Firestore.firestore(database: "stitchfin").settings = settings
                        
                        Functions.functions().useEmulator(withHost: "localhost", port: 5001)
                        Auth.auth().useEmulator(withHost: "localhost", port: 9099)
                        
                        print("🧪 EMULATOR MODE: Firestore=8080, Functions=5001, Auth=9099")
                    }
                    #endif
                    
                    // Wire TipService with shared NotificationService
                    TipService.shared.configure(notificationService: notificationService)

                    // Initialize memory management
                    initializeMemoryManagement()
                    
                    // 🆕 Recover any interrupted background uploads from previous session
                    backgroundUploadManager.recoverInterruptedUploads()
                    
                    print("📱 APP STARTUP: Services initialized")
                    print("📤 Background Upload: Recovery check complete")
                    print("📱 FCM: Automatic via FCMPushManager")
                    print("📱 Notifications: Automatic via NotificationViewModel")
                    print("🧠 Memory: VideoPreloadingService ready")
                    
                    // Version gate check — 1 Firestore read, cached 1 hour
                    Task {
                        await versionGate.checkVersion()
                    }
                    
                    // Print config status if debug mode
                    if Config.Features.enableDebugLogging {
                        Config.printConfigurationStatus()
                    }
                    
                    // Auto-follow handled by Cloud Function #24 (onUserCreated) — no client-side backfill needed
                    
                    // Post-login setup for returning users
                    // Force token refresh before any Firestore calls — prevents
                    // "Missing or insufficient permissions" on badges/subs/plans listeners
                    // that fire before Firestore receives the auth token.
                    Task {
                        if let user = Auth.auth().currentUser {
                            _ = try? await user.getIDToken(forcingRefresh: true)
                            SubscriptionService.shared.setCurrentUserEmail(user.email)
                            await CommunityService.shared.autoJoinOfficialCommunity(
                                userID: user.uid,
                                username: user.displayName ?? "user_\(user.uid.prefix(6))",
                                displayName: user.displayName ?? "User"
                            )
                        }
                    }
                }
        }
    }
    
    // MARK: - Scene Phase Cleanup
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            performBackgroundCleanup()
            
        case .active:
            performForegroundResume()
            
        case .inactive:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Background Cleanup (Battery Fix)
    
    /// Stops ALL background-draining activity when app enters background.
    /// This is the single biggest battery optimization — kills:
    /// - Snapshot listeners (persistent WebSocket connections)
    /// - Singleton service timers (BatchingService, XP, coins, heartbeats)
    /// - Video preloading / AVPlayer instances
    /// - Animation timers via notification broadcast
    ///
    /// Cost: 0. Everything resumes on foreground return.
    private func performBackgroundCleanup() {
        print("🔋 BACKGROUND CLEANUP: Stopping all background activity")
        
        // 1. Kill all background tasks via the existing kill switch
        BackgroundActivityManager.shared.killAllBackgroundActivity(reason: "App entering background")
        
        // 2. Stop notification snapshot listener (persistent WebSocket)
        notificationService.stopListening()
        print("🔋 STOPPED: NotificationService snapshot listener")
        
        // 3. Flush and stop CommunityXPService timer
        Task {
            await CommunityXPService.shared.onAppBackground()
        }
        print("🔋 STOPPED: CommunityXPService flush timer")
        
        // 4. Stop all video preloading and release AVPlayers
        VideoPreloadingService.shared.clearAllPlayers()
        print("🔋 STOPPED: VideoPreloadingService — all AVPlayers released")
        
        // 5. Disk cache cleanup (already existed)
        VideoDiskCache.shared.cleanupExpired()
        ThumbnailCache.shared.clear()
        
        // 6. Broadcast timer kill to all views listening for it
        // This catches: ProfileAnimations, EmberParticlesView, FloatingIcon,
        // AnnouncementOverlayView, and any other timer-based views
        NotificationCenter.default.post(name: .killAllBackgroundTimers, object: nil)
        print("🔋 BROADCAST: killAllBackgroundTimers sent")
        
        // 7. Re-check version gate on next foreground (cache handles cost)
        // Nothing to do here — checkVersion() is called in .active
        
        print("🔋 BACKGROUND CLEANUP: Complete — all drains stopped")
    }
    
    // MARK: - Foreground Resume
    
    /// Resumes essential services when app returns to foreground.
    /// Only restarts what's needed — the current visible tab handles its own setup.
    private func performForegroundResume() {
        print("🔋 FOREGROUND RESUME: Restarting essential services")
        
        // 1. Re-check version gate (1-hour TTL cache — usually 0 reads)
        Task {
            await versionGate.checkVersion()
        }
        
        // 2. Restart notification listener if user is logged in
        if let userID = Auth.auth().currentUser?.uid {
            notificationService.startListening(for: userID) { _ in
                // Notifications handled by NotificationViewModel
            }
            print("🔋 RESUMED: NotificationService snapshot listener")
        }
        
        // 3. Discovery cache invalidation if stale (>10 min in background)
        // DiscoveryService handles this internally via TTL
        
        print("🔋 FOREGROUND RESUME: Complete")
    }
    
    // MARK: - Memory Management Setup
    
    /// Soft update banner — shown at bottom of screen when forceUpdate == false
    private var updateBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 20))
                .foregroundColor(.cyan)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Update Available")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Build \(versionGate.minimumBuild)+ recommended")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Button {
                if !versionGate.testflightURL.isEmpty,
                   let url = URL(string: versionGate.testflightURL) {
                    UIApplication.shared.open(url)
                } else if let url = URL(string: "itms-beta://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Update")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.cyan)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 100) // Above tab bar
    }
    
    private func initializeMemoryManagement() {
        // Pre-warm the preloading service (triggers memory observers)
        _ = VideoPreloadingService.shared
        
        // Memory warning — emergency eviction
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("🔴 MEMORY WARNING: Running emergency cleanup")
            VideoDiskCache.shared.emergencyCleanup(keepCount: 5)
            ThumbnailCache.shared.clear()
        }
        
        // Log initial state
        VideoPreloadingService.shared.helloWorldTest()
    }
}

// MARK: - App Toast Overlay

struct AppToastOverlay: View {
    @ObservedObject var notificationService: NotificationService
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(notificationService.pendingToasts.prefix(3), id: \.id) { toast in
                AppToastCard(toast: toast) {
                    // FIXED: Remove toast directly from array
                    removeToast(toast.id)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                ))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: notificationService.pendingToasts.count)
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }
    
    private func removeToast(_ id: String) {
        withAnimation {
            notificationService.pendingToasts.removeAll { $0.id == id }
        }
    }
}

// MARK: - App Toast Card

struct AppToastCard: View {
    let toast: NotificationToast
    let onDismiss: () -> Void
    
    @State private var isPressed = false
    @State private var shouldDismiss = false
    
    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 12) {
                // Notification type icon
                ZStack {
                    Circle()
                        .fill(toast.type.appToastColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: toast.type.appToastIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(toast.type.appToastColor)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(toast.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(toast.message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {
            // Handle press completed
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
        .onAppear {
            // Auto-dismiss after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + toast.appToastDuration) {
                if !shouldDismiss {
                    shouldDismiss = true
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Toast Type Extensions

extension StitchNotificationType {
    var appToastColor: Color {
        switch self {
        case .hype: return .red
        case .cool: return .blue
        case .follow: return .green
        case .reply: return .purple
        case .mention: return .orange
        case .tierUpgrade: return .yellow
        case .milestone: return .pink
        case .system: return .gray
        case .goLive: return .red
        case .communityPost: return .cyan
        case .communityXP: return .green
        case .tip: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case .subscription: return .purple
        }
    }
    
    var appToastIcon: String {
        switch self {
        case .hype: return "flame.fill"
        case .cool: return "snowflake"
        case .follow: return "person.badge.plus.fill"
        case .reply: return "bubble.left.fill"
        case .mention: return "at"
        case .tierUpgrade: return "arrow.up.circle.fill"
        case .milestone: return "trophy.fill"
        case .system: return "gear.circle.fill"
        case .goLive: return "video.fill"
        case .communityPost: return "bubble.left.and.bubble.right.fill"
        case .communityXP: return "star.fill"
        case .tip: return "dollarsign.circle.fill"
        case .subscription: return "star.circle.fill"
        }
    }
}

extension NotificationToast {
    var appToastDuration: TimeInterval {
        switch type {
        case .hype, .cool: return 3.0
        case .follow: return 4.0
        case .reply, .mention: return 5.0
        case .tierUpgrade, .milestone: return 6.0
        case .goLive: return 6.0
        case .communityPost, .communityXP: return 4.0
        case .system: return 8.0
        case .tip: return 4.0
        case .subscription: return 5.0
        }
    }
}
