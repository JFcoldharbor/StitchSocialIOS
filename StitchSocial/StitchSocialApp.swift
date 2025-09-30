import SwiftUI
import FirebaseCore
import FirebaseAuth
import UserNotifications
import FirebaseMessaging

@main
struct StitchSocialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Shared services for entire app
    @StateObject private var notificationService = NotificationService()
    @StateObject private var authService = AuthService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationService)
                .environmentObject(authService)
                .overlay(
                    // Toast notification overlay above all content
                    AppToastOverlay(notificationService: notificationService)
                        .allowsHitTesting(false) // Don't block touches to main content
                )
                .onAppear {
                    // Inject notification service into auth service
                    authService.setNotificationService(notificationService)
                    
                    // Start notification listener if user already authenticated
                    if let currentUserID = Auth.auth().currentUser?.uid {
                        print("📔 APP STARTUP: Starting notification listener for user \(currentUserID)")
                        notificationService.startNotificationListener(for: currentUserID)
                    } else {
                        print("📔 APP STARTUP: No authenticated user found")
                    }
                }
        }
    }
}

// MARK: - App Toast Overlay (Renamed to avoid conflicts)

struct AppToastOverlay: View {
    @ObservedObject var notificationService: NotificationService
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(notificationService.pendingToasts.prefix(3), id: \.id) { toast in
                AppToastCard(toast: toast) {
                    notificationService.dismissToast(toastID: toast.id)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                ))
            }
            
            Spacer()
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: notificationService.pendingToasts.count)
        .padding(.top, 60) // Below status bar and notch
        .padding(.horizontal, 16)
    }
}

// MARK: - App Toast Card (Renamed to avoid conflicts)

struct AppToastCard: View {
    let toast: NotificationToast
    let onDismiss: () -> Void
    
    @State private var isPressed = false
    
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
            // Auto-dismiss after duration if not manually dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + toast.appToastDuration) {
                onDismiss()
            }
        }
    }
}

// MARK: - Toast Type Extensions (App-specific names to avoid conflicts)

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
        case .system: return 8.0
        }
    }
}
