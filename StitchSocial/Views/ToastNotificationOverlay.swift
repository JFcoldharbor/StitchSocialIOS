//
//  ToastNotificationOverlay.swift
//  StitchSocial
//
//  Layer 8: Views - Toast Notification Display System
//  UPDATED: Removed dismissToast - toasts auto-dismiss only
//

import SwiftUI

// MARK: - Toast Notification Overlay

struct ToastNotificationOverlay: View {
    @ObservedObject var notificationService: NotificationService
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(notificationService.pendingToasts.prefix(3), id: \.id) { toast in
                ToastView(toast: toast) {
                    // Toast will auto-dismiss via timer - no manual dismiss method
                    // Remove toast from array directly
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

// MARK: - Individual Toast View

struct ToastView: View {
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
                        .fill(toast.type.toastColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: toast.type.toastIconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(toast.type.toastColor)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + toast.displayDuration) {
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
    var toastColor: Color {
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
        }
    }
    
    var toastIconName: String {
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
        }
    }
}

// MARK: - Toast Display Duration Extension

extension NotificationToast {
    var displayDuration: TimeInterval {
        switch type {
        case .hype, .cool: return 3.0
        case .follow: return 4.0
        case .reply, .mention: return 5.0
        case .tierUpgrade, .milestone: return 6.0
        case .system: return 8.0
        case .goLive: return 6.0
        case .communityPost, .communityXP: return 4.0
        }
    }
}

// MARK: - Preview Support

struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ToastView(
                toast: NotificationToast(
                    type: .hype,
                    title: "🔥 Your video got hyped!",
                    message: "testuser hyped your video",
                    senderUsername: "testuser",
                    payload: [:]
                ),
                onDismiss: {}
            )
            
            ToastView(
                toast: NotificationToast(
                    type: .follow,
                    title: "👥 New Follower",
                    message: "newuser started following you",
                    senderUsername: "newuser",
                    payload: [:]
                ),
                onDismiss: {}
            )
            
            ToastView(
                toast: NotificationToast(
                    type: .tierUpgrade,
                    title: "🎉 Tier Upgraded!",
                    message: "You've reached Rising tier!",
                    senderUsername: "",
                    payload: [:]
                ),
                onDismiss: {}
            )
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
