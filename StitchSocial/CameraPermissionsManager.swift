//
//  CameraPermissionsManager.swift
//  CleanBeta
//
//  Layer 4: Core Services - Camera & Microphone Permissions Management
//  Handles permission requests, state tracking, and user guidance
//  Clean integration with recording flow and proper error handling
//

import Foundation
import AVFoundation
import SwiftUI

/// Manages camera and microphone permissions with comprehensive UI guidance
/// Provides clean integration with recording flow and handles all permission states
@MainActor
class CameraPermissionsManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var microphonePermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var isCheckingPermissions: Bool = false
    @Published var permissionError: PermissionError?
    @Published var showingPermissionAlert: Bool = false
    @Published var showingSettingsAlert: Bool = false
    
    // MARK: - Computed Properties
    
    var canRecord: Bool {
        return cameraPermissionStatus == .authorized && microphonePermissionStatus == .authorized
    }
    
    var needsPermissions: Bool {
        return cameraPermissionStatus != .authorized || microphonePermissionStatus != .authorized
    }
    
    var hasRequestedPermissions: Bool {
        return cameraPermissionStatus != .notDetermined && microphonePermissionStatus != .notDetermined
    }
    
    var permissionsSummary: PermissionsSummary {
        return PermissionsSummary(
            camera: cameraPermissionStatus,
            microphone: microphonePermissionStatus,
            canRecord: canRecord,
            needsAction: needsPermissions
        )
    }
    
    // MARK: - Initialization
    
    init() {
        updatePermissionStatus()
        setupPermissionObservers()
    }
    
    // MARK: - Public Interface
    
    /// Requests all necessary permissions for recording
    /// Returns true if all permissions granted, false otherwise
    func requestRecordingPermissions() async -> Bool {
        await MainActor.run {
            self.isCheckingPermissions = true
            self.permissionError = nil
        }
        
        do {
            // Request camera permission first
            let cameraGranted = try await requestCameraPermission()
            
            // Request microphone permission
            let microphoneGranted = try await requestMicrophonePermission()
            
            await MainActor.run {
                self.updatePermissionStatus()
                self.isCheckingPermissions = false
            }
            
            let allGranted = cameraGranted && microphoneGranted
            
            if !allGranted {
                await handlePermissionDenied()
            }
            
            print("📹 PERMISSIONS: Recording permissions - Camera: \(cameraGranted), Microphone: \(microphoneGranted)")
            return allGranted
            
        } catch {
            await MainActor.run {
                self.permissionError = error as? PermissionError ?? .unknown(error.localizedDescription)
                self.isCheckingPermissions = false
                self.showingPermissionAlert = true
            }
            
            print("❌ PERMISSIONS: Permission request failed - \(error.localizedDescription)")
            return false
        }
    }
    
    /// Checks current permission status without requesting
    func checkPermissionStatus() {
        updatePermissionStatus()
    }
    
    /// Opens Settings app for permission management
    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    /// Validates permissions before starting recording
    func validateRecordingPermissions() throws {
        updatePermissionStatus()
        
        guard cameraPermissionStatus == .authorized else {
            throw PermissionError.cameraAccessDenied("Camera access is required for recording")
        }
        
        guard microphonePermissionStatus == .authorized else {
            throw PermissionError.microphoneAccessDenied("Microphone access is required for recording")
        }
    }
    
    /// Gets user-friendly guidance for current permission state
    func getPermissionGuidance() -> PermissionGuidance {
        switch (cameraPermissionStatus, microphonePermissionStatus) {
        case (.authorized, .authorized):
            return PermissionGuidance(
                title: "Ready to Record",
                message: "All permissions granted. You can start recording!",
                actionTitle: nil,
                action: nil,
                type: .success
            )
            
        case (.notDetermined, _), (_, .notDetermined):
            return PermissionGuidance(
                title: "Permissions Needed",
                message: "Stitch needs access to your camera and microphone to record videos.",
                actionTitle: "Grant Permissions",
                action: { Task { await self.requestRecordingPermissions() } },
                type: .request
            )
            
        case (.denied, _), (_, .denied), (.restricted, _), (_, .restricted):
            return PermissionGuidance(
                title: "Permissions Required",
                message: "Please enable camera and microphone access in Settings to record videos.",
                actionTitle: "Open Settings",
                action: { self.openSettings() },
                type: .settings
            )
            
        default:
            return PermissionGuidance(
                title: "Permission Error",
                message: "There was an issue with camera permissions. Please try again.",
                actionTitle: "Retry",
                action: { Task { await self.requestRecordingPermissions() } },
                type: .error
            )
        }
    }
    
    // MARK: - Private Permission Methods
    
    /// Requests camera permission
    private func requestCameraPermission() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Requests microphone permission
    private func requestMicrophonePermission() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Updates current permission status
    private func updatePermissionStatus() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphonePermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    /// Handles permission denial with appropriate UI
    private func handlePermissionDenied() async {
        await MainActor.run {
            if self.cameraPermissionStatus == .denied || self.microphonePermissionStatus == .denied {
                self.showingSettingsAlert = true
            } else {
                self.permissionError = .partialAccess("Some permissions were not granted")
                self.showingPermissionAlert = true
            }
        }
    }
    
    /// Sets up observers for permission changes
    private func setupPermissionObservers() {
        // Monitor app becoming active to check for permission changes
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePermissionStatus()
            }
        }
    }
    
    // MARK: - Error Handling
    
    func clearError() {
        permissionError = nil
        showingPermissionAlert = false
        showingSettingsAlert = false
    }
    
    func handlePermissionAlert() -> Alert {
        let guidance = getPermissionGuidance()
        
        if guidance.type == .settings {
            return Alert(
                title: Text(guidance.title),
                message: Text(guidance.message),
                primaryButton: .default(Text("Settings")) {
                    self.openSettings()
                },
                secondaryButton: .cancel()
            )
        } else {
            return Alert(
                title: Text(guidance.title),
                message: Text(guidance.message),
                dismissButton: .default(Text("OK")) {
                    self.clearError()
                }
            )
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SwiftUI Integration

/// Permission request view for clean UI integration
struct PermissionRequestView: View {
    @ObservedObject var permissionsManager: CameraPermissionsManager
    let onPermissionsGranted: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Permission icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [StitchColors.primary.opacity(0.3), StitchColors.secondary.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: permissionsManager.needsPermissions ? "camera.fill" : "checkmark.circle.fill")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(permissionsManager.needsPermissions ? .white : .green)
                }
                
                // Permission guidance
                let guidance = permissionsManager.getPermissionGuidance()
                
                VStack(spacing: 16) {
                    Text(guidance.title)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(guidance.message)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Permission status indicators
                VStack(spacing: 12) {
                    PermissionStatusRow(
                        icon: "camera.fill",
                        title: "Camera",
                        status: permissionsManager.cameraPermissionStatus
                    )
                    
                    PermissionStatusRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        status: permissionsManager.microphonePermissionStatus
                    )
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    if let actionTitle = guidance.actionTitle, let action = guidance.action {
                        Button(actionTitle) {
                            action()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [StitchColors.primary, StitchColors.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                        .disabled(permissionsManager.isCheckingPermissions)
                    }
                    
                    if permissionsManager.canRecord {
                        Button("Continue") {
                            onPermissionsGranted()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green)
                        .cornerRadius(25)
                    } else {
                        Button("Cancel") {
                            onCancel()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(22)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
                
                if permissionsManager.isCheckingPermissions {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
        }
        .onAppear {
            permissionsManager.checkPermissionStatus()
        }
        .alert(isPresented: $permissionsManager.showingPermissionAlert) {
            permissionsManager.handlePermissionAlert()
        }
        .onChange(of: permissionsManager.canRecord) {
            if permissionsManager.canRecord {
                onPermissionsGranted()
            }
        }
    }
}

/// Individual permission status row
struct PermissionStatusRow: View {
    let icon: String
    let title: String
    let status: AVAuthorizationStatus
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
            
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundColor(statusColor)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var statusIcon: String {
        switch status {
        case .authorized: return "checkmark.circle.fill"
        case .denied, .restricted: return "xmark.circle.fill"
        case .notDetermined: return "clock.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .authorized: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }
    
    private var statusText: String {
        switch status {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Requested"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Data Models

struct PermissionsSummary {
    let camera: AVAuthorizationStatus
    let microphone: AVAuthorizationStatus
    let canRecord: Bool
    let needsAction: Bool
}

struct PermissionGuidance {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let type: GuidanceType
    
    enum GuidanceType {
        case success, request, settings, error
    }
}

enum PermissionError: Error, LocalizedError {
    case cameraAccessDenied(String)
    case microphoneAccessDenied(String)
    case partialAccess(String)
    case deviceRestricted(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .cameraAccessDenied(let msg): return "Camera Access Denied: \(msg)"
        case .microphoneAccessDenied(let msg): return "Microphone Access Denied: \(msg)"
        case .partialAccess(let msg): return "Partial Access: \(msg)"
        case .deviceRestricted(let msg): return "Device Restricted: \(msg)"
        case .unknown(let msg): return "Unknown Error: \(msg)"
        }
    }
}
