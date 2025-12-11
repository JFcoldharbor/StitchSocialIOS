//
//  CollectionErrorHandler.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionErrorHandler.swift
//  StitchSocial
//
//  Layer 4: Core Services - Centralized Error Handling
//  Dependencies: Foundation, SwiftUI
//  Features: Error categorization, user-friendly messages, retry actions, error logging, alerts
//  CREATED: Phase 7 - Collections feature Polish
//

import Foundation
import SwiftUI
import Combine

/// Centralized error handling for Collections feature
/// Provides user-friendly messages, retry actions, and error logging
@MainActor
class CollectionErrorHandler: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CollectionErrorHandler()
    
    // MARK: - Published State
    
    /// Current error to display (if any)
    @Published var currentError: CollectionError?
    
    /// Whether to show error alert
    @Published var showErrorAlert: Bool = false
    
    /// Whether to show error banner
    @Published var showErrorBanner: Bool = false
    
    /// Error history for debugging
    @Published private(set) var errorHistory: [ErrorLogEntry] = []
    
    // MARK: - Configuration
    
    /// Maximum errors to keep in history
    var maxErrorHistory: Int = 50
    
    /// Whether to log errors to console
    var enableConsoleLogging: Bool = true
    
    /// Whether to send errors to analytics
    var enableAnalytics: Bool = true
    
    // MARK: - Private Properties
    
    private var dismissTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        print("⚠️ ERROR HANDLER: Initialized")
    }
    
    // MARK: - Error Handling
    
    /// Handle an error with appropriate UI feedback
    func handle(
        _ error: Error,
        context: ErrorContext,
        showAlert: Bool = false,
        showBanner: Bool = true,
        retryAction: (() -> Void)? = nil
    ) {
        let collectionError = categorize(error, context: context)
        
        // Log error
        log(collectionError, context: context)
        
        // Update current error
        currentError = collectionError
        
        // Show appropriate UI
        if showAlert {
            showErrorAlert = true
        } else if showBanner {
            showErrorBanner = true
            scheduleBannerDismissal()
        }
        
        // Store retry action
        if let retryAction = retryAction {
            currentError?.retryAction = retryAction
        }
    }
    
    /// Handle error and return a user-friendly message
    func handleAndGetMessage(_ error: Error, context: ErrorContext) -> String {
        let collectionError = categorize(error, context: context)
        log(collectionError, context: context)
        return collectionError.userMessage
    }
    
    /// Dismiss current error
    func dismissError() {
        currentError = nil
        showErrorAlert = false
        showErrorBanner = false
        dismissTimer?.invalidate()
    }
    
    /// Retry the failed action
    func retry() {
        currentError?.retryAction?()
        dismissError()
    }
    
    // MARK: - Error Categorization
    
    /// Categorize a raw error into a CollectionError
    func categorize(_ error: Error, context: ErrorContext) -> CollectionError {
        // Check if already a CollectionError
        if let collectionError = error as? CollectionError {
            return collectionError
        }
        
        // Check for specific error types
        let nsError = error as NSError
        
        // Network errors
        if nsError.domain == NSURLErrorDomain {
            return categorizeNetworkError(nsError, context: context)
        }
        
        // Firebase errors
        if nsError.domain.contains("Firebase") || nsError.domain.contains("FIRFirestore") {
            return categorizeFirebaseError(nsError, context: context)
        }
        
        // Storage errors
        if nsError.domain.contains("Storage") {
            return categorizeStorageError(nsError, context: context)
        }
        
        // Cache errors
        if let cacheError = error as? CacheError {
            return categorizeCacheError(cacheError, context: context)
        }
        
        // Collection service errors
        if let serviceError = error as? CollectionServiceError {
            return categorizeServiceError(serviceError, context: context)
        }
        
        // Coordinator errors
        if let coordinatorError = error as? CoordinatorError {
            return categorizeCoordinatorError(coordinatorError, context: context)
        }
        
        // Default unknown error
        return CollectionError(
            type: .unknown,
            context: context,
            underlyingError: error,
            userMessage: "Something went wrong. Please try again.",
            technicalMessage: error.localizedDescription,
            isRetryable: true
        )
    }
    
    private func categorizeNetworkError(_ error: NSError, context: ErrorContext) -> CollectionError {
        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return CollectionError(
                type: .noInternet,
                context: context,
                underlyingError: error,
                userMessage: "No internet connection. Please check your network and try again.",
                technicalMessage: "NSURLError: \(error.code)",
                isRetryable: true
            )
            
        case NSURLErrorTimedOut:
            return CollectionError(
                type: .timeout,
                context: context,
                underlyingError: error,
                userMessage: "The request timed out. Please try again.",
                technicalMessage: "Request timeout",
                isRetryable: true
            )
            
        case NSURLErrorCancelled:
            return CollectionError(
                type: .cancelled,
                context: context,
                underlyingError: error,
                userMessage: "The operation was cancelled.",
                technicalMessage: "Request cancelled",
                isRetryable: false
            )
            
        default:
            return CollectionError(
                type: .networkError,
                context: context,
                underlyingError: error,
                userMessage: "A network error occurred. Please try again.",
                technicalMessage: "NSURLError: \(error.code) - \(error.localizedDescription)",
                isRetryable: true
            )
        }
    }
    
    private func categorizeFirebaseError(_ error: NSError, context: ErrorContext) -> CollectionError {
        // Common Firestore error codes
        switch error.code {
        case 7: // PERMISSION_DENIED
            return CollectionError(
                type: .permissionDenied,
                context: context,
                underlyingError: error,
                userMessage: "You don't have permission to perform this action.",
                technicalMessage: "Firestore permission denied",
                isRetryable: false
            )
            
        case 5: // NOT_FOUND
            return CollectionError(
                type: .notFound,
                context: context,
                underlyingError: error,
                userMessage: "The requested content was not found.",
                technicalMessage: "Firestore document not found",
                isRetryable: false
            )
            
        case 14: // UNAVAILABLE
            return CollectionError(
                type: .serverUnavailable,
                context: context,
                underlyingError: error,
                userMessage: "The server is temporarily unavailable. Please try again later.",
                technicalMessage: "Firestore unavailable",
                isRetryable: true
            )
            
        case 8: // RESOURCE_EXHAUSTED
            return CollectionError(
                type: .rateLimited,
                context: context,
                underlyingError: error,
                userMessage: "Too many requests. Please wait a moment and try again.",
                technicalMessage: "Firestore rate limit exceeded",
                isRetryable: true
            )
            
        default:
            return CollectionError(
                type: .serverError,
                context: context,
                underlyingError: error,
                userMessage: "A server error occurred. Please try again.",
                technicalMessage: "Firestore error: \(error.code)",
                isRetryable: true
            )
        }
    }
    
    private func categorizeStorageError(_ error: NSError, context: ErrorContext) -> CollectionError {
        switch error.code {
        case -13000: // Unknown
            return CollectionError(
                type: .uploadFailed,
                context: context,
                underlyingError: error,
                userMessage: "Upload failed. Please try again.",
                technicalMessage: "Storage unknown error",
                isRetryable: true
            )
            
        case -13010: // Object not found
            return CollectionError(
                type: .notFound,
                context: context,
                underlyingError: error,
                userMessage: "The file was not found.",
                technicalMessage: "Storage object not found",
                isRetryable: false
            )
            
        case -13013: // Quota exceeded
            return CollectionError(
                type: .quotaExceeded,
                context: context,
                underlyingError: error,
                userMessage: "Storage quota exceeded. Please free up space or upgrade your plan.",
                technicalMessage: "Storage quota exceeded",
                isRetryable: false
            )
            
        case -13021: // Cancelled
            return CollectionError(
                type: .cancelled,
                context: context,
                underlyingError: error,
                userMessage: "Upload was cancelled.",
                technicalMessage: "Storage upload cancelled",
                isRetryable: false
            )
            
        default:
            return CollectionError(
                type: .uploadFailed,
                context: context,
                underlyingError: error,
                userMessage: "Upload failed. Please try again.",
                technicalMessage: "Storage error: \(error.code)",
                isRetryable: true
            )
        }
    }
    
    private func categorizeCacheError(_ error: CacheError, context: ErrorContext) -> CollectionError {
        switch error {
        case .insufficientSpace:
            return CollectionError(
                type: .insufficientStorage,
                context: context,
                underlyingError: error,
                userMessage: "Not enough storage space. Free up some space and try again.",
                technicalMessage: "Cache insufficient space",
                isRetryable: true
            )
            
        case .invalidURL:
            return CollectionError(
                type: .invalidData,
                context: context,
                underlyingError: error,
                userMessage: "Invalid video URL.",
                technicalMessage: "Cache invalid URL",
                isRetryable: false
            )
            
        case .downloadFailed:
            return CollectionError(
                type: .downloadFailed,
                context: context,
                underlyingError: error,
                userMessage: "Download failed. Please try again.",
                technicalMessage: "Cache download failed",
                isRetryable: true
            )
            
        default:
            return CollectionError(
                type: .cacheError,
                context: context,
                underlyingError: error,
                userMessage: "A caching error occurred.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
        }
    }
    
    private func categorizeServiceError(_ error: CollectionServiceError, context: ErrorContext) -> CollectionError {
        switch error {
        case .draftNotFound:
            return CollectionError(
                type: .notFound,
                context: context,
                underlyingError: error,
                userMessage: "Draft not found. It may have been deleted.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .collectionNotFound:
            return CollectionError(
                type: .notFound,
                context: context,
                underlyingError: error,
                userMessage: "Collection not found.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .draftLimitReached(let limit):
            return CollectionError(
                type: .limitReached,
                context: context,
                underlyingError: error,
                userMessage: "You've reached the maximum of \(limit) drafts. Delete some drafts to create new ones.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .segmentLimitReached(let limit):
            return CollectionError(
                type: .limitReached,
                context: context,
                underlyingError: error,
                userMessage: "Maximum of \(limit) segments reached.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .validationFailed(let errors):
            return CollectionError(
                type: .validationFailed,
                context: context,
                underlyingError: error,
                userMessage: errors.first ?? "Please fix the errors and try again.",
                technicalMessage: errors.joined(separator: ", "),
                isRetryable: false
            )
            
        case .publishingFailed:
            return CollectionError(
                type: .publishFailed,
                context: context,
                underlyingError: error,
                userMessage: "Failed to publish collection. Please try again.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
            
        case .unauthorized:
            return CollectionError(
                type: .permissionDenied,
                context: context,
                underlyingError: error,
                userMessage: "You don't have permission to perform this action.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .networkError:
            return CollectionError(
                type: .networkError,
                context: context,
                underlyingError: error,
                userMessage: "A network error occurred. Please try again.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
        }
    }
    
    private func categorizeCoordinatorError(_ error: CoordinatorError, context: ErrorContext) -> CollectionError {
        switch error {
        case .videoLoadFailed:
            return CollectionError(
                type: .videoLoadFailed,
                context: context,
                underlyingError: error,
                userMessage: "Failed to load video. Please try selecting a different video.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
            
        case .thumbnailGenerationFailed:
            return CollectionError(
                type: .processingFailed,
                context: context,
                underlyingError: error,
                userMessage: "Failed to generate thumbnail.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
            
        case .uploadFailed:
            return CollectionError(
                type: .uploadFailed,
                context: context,
                underlyingError: error,
                userMessage: "Upload failed. Please try again.",
                technicalMessage: error.localizedDescription,
                isRetryable: true
            )
            
        case .noDraftID:  // ADD THIS CASE
            return CollectionError(
                type: .invalidData,
                context: context,
                underlyingError: error,
                userMessage: "Unable to save. Please try creating a new draft.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .collectionNotFound:
            return CollectionError(
                type: .notFound,
                context: context,
                underlyingError: error,
                userMessage: "Collection not found.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
            
        case .unauthorized:
            return CollectionError(
                type: .permissionDenied,
                context: context,
                underlyingError: error,
                userMessage: "You don't have permission to perform this action.",
                technicalMessage: error.localizedDescription,
                isRetryable: false
            )
        }
    }
    
    // MARK: - Logging
    
    private func log(_ error: CollectionError, context: ErrorContext) {
        let entry = ErrorLogEntry(
            error: error,
            context: context,
            timestamp: Date()
        )
        
        // Add to history
        errorHistory.insert(entry, at: 0)
        
        // Trim history
        if errorHistory.count > maxErrorHistory {
            errorHistory = Array(errorHistory.prefix(maxErrorHistory))
        }
        
        // Console logging
        if enableConsoleLogging {
            print("❌ ERROR [\(context.rawValue)]: \(error.technicalMessage)")
        }
        
        // Analytics logging
        if enableAnalytics {
            logToAnalytics(entry)
        }
    }
    
    private func logToAnalytics(_ entry: ErrorLogEntry) {
        // Would send to analytics service
        // Analytics.log(event: "collection_error", properties: [...])
    }
    
    // MARK: - Banner Management
    
    private func scheduleBannerDismissal() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showErrorBanner = false
            }
        }
    }
    
    // MARK: - Error History
    
    /// Clear error history
    func clearHistory() {
        errorHistory.removeAll()
    }
    
    /// Export error history for debugging
    func exportHistory() -> String {
        let entries = errorHistory.map { entry in
            """
            [\(entry.formattedTimestamp)] [\(entry.context.rawValue)]
            Type: \(entry.error.type.rawValue)
            Message: \(entry.error.userMessage)
            Technical: \(entry.error.technicalMessage)
            """
        }
        
        return entries.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - Collection Error

/// Structured error for Collections feature
struct CollectionError: Error, Identifiable {
    let id = UUID()
    let type: CollectionErrorType
    let context: ErrorContext
    let underlyingError: Error?
    let userMessage: String
    let technicalMessage: String
    let isRetryable: Bool
    var retryAction: (() -> Void)?
    
    /// Icon for the error type
    var icon: String {
        type.icon
    }
    
    /// Color for the error type
    var color: Color {
        type.color
    }
}

/// Types of collection errors
enum CollectionErrorType: String {
    // Network
    case noInternet = "no_internet"
    case networkError = "network_error"
    case timeout = "timeout"
    case serverUnavailable = "server_unavailable"
    case serverError = "server_error"
    case rateLimited = "rate_limited"
    
    // Authentication/Authorization
    case permissionDenied = "permission_denied"
    case unauthorized = "unauthorized"
    
    // Data
    case notFound = "not_found"
    case invalidData = "invalid_data"
    case validationFailed = "validation_failed"
    
    // Operations
    case uploadFailed = "upload_failed"
    case downloadFailed = "download_failed"
    case publishFailed = "publish_failed"
    case processingFailed = "processing_failed"
    case videoLoadFailed = "video_load_failed"
    
    // Storage
    case insufficientStorage = "insufficient_storage"
    case quotaExceeded = "quota_exceeded"
    case cacheError = "cache_error"
    
    // Limits
    case limitReached = "limit_reached"
    
    // Other
    case cancelled = "cancelled"
    case unknown = "unknown"
    
    var icon: String {
        switch self {
        case .noInternet:
            return "wifi.slash"
        case .networkError, .timeout, .serverUnavailable, .serverError:
            return "exclamationmark.icloud"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        case .permissionDenied, .unauthorized:
            return "lock.shield"
        case .notFound:
            return "magnifyingglass"
        case .invalidData, .validationFailed:
            return "exclamationmark.triangle"
        case .uploadFailed:
            return "arrow.up.circle.badge.xmark"
        case .downloadFailed:
            return "arrow.down.circle.badge.xmark"
        case .publishFailed:
            return "paperplane.badge.xmark"
        case .processingFailed, .videoLoadFailed:
            return "gearshape.badge.xmark"
        case .insufficientStorage, .quotaExceeded:
            return "externaldrive.badge.xmark"
        case .cacheError:
            return "internaldrive.badge.xmark"
        case .limitReached:
            return "exclamationmark.octagon"
        case .cancelled:
            return "xmark.circle"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .noInternet, .networkError, .timeout:
            return .orange
        case .serverUnavailable, .serverError, .rateLimited:
            return .red
        case .permissionDenied, .unauthorized:
            return .red
        case .notFound:
            return .gray
        case .invalidData, .validationFailed:
            return .yellow
        case .uploadFailed, .downloadFailed, .publishFailed:
            return .red
        case .processingFailed, .videoLoadFailed:
            return .orange
        case .insufficientStorage, .quotaExceeded, .cacheError:
            return .purple
        case .limitReached:
            return .orange
        case .cancelled:
            return .gray
        case .unknown:
            return .red
        }
    }
}

/// Context where error occurred
enum ErrorContext: String {
    case draftCreation = "draft_creation"
    case draftLoading = "draft_loading"
    case draftSaving = "draft_saving"
    case draftDeleting = "draft_deleting"
    case segmentUpload = "segment_upload"
    case segmentProcessing = "segment_processing"
    case publishing = "publishing"
    case collectionLoading = "collection_loading"
    case collectionPlaying = "collection_playing"
    case progressSaving = "progress_saving"
    case caching = "caching"
    case general = "general"
}

/// Error log entry for history
struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let error: CollectionError
    let context: ErrorContext
    let timestamp: Date
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - Error Banner View

/// Reusable error banner component
struct ErrorBannerView: View {
    let error: CollectionError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.icon)
                .font(.title3)
                .foregroundColor(error.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.userMessage)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if error.isRetryable, let onRetry = onRetry {
                Button("Retry") {
                    onRetry()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            }
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .padding(.horizontal)
    }
}

// MARK: - Error Alert Modifier

/// View modifier for showing error alerts
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler: CollectionErrorHandler
    
    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorHandler.showErrorAlert,
                presenting: errorHandler.currentError
            ) { error in
                if error.isRetryable {
                    Button("Retry") {
                        errorHandler.retry()
                    }
                }
                Button("OK", role: .cancel) {
                    errorHandler.dismissError()
                }
            } message: { error in
                Text(error.userMessage)
            }
    }
}

extension View {
    /// Add error alert handling
    func errorAlert(_ handler: CollectionErrorHandler) -> some View {
        modifier(ErrorAlertModifier(errorHandler: handler))
    }
}

// MARK: - Error Banner Modifier

/// View modifier for showing error banners
struct ErrorBannerModifier: ViewModifier {
    @ObservedObject var errorHandler: CollectionErrorHandler
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if errorHandler.showErrorBanner, let error = errorHandler.currentError {
                ErrorBannerView(
                    error: error,
                    onDismiss: {
                        errorHandler.dismissError()
                    },
                    onRetry: error.isRetryable ? {
                        errorHandler.retry()
                    } : nil
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(), value: errorHandler.showErrorBanner)
                .padding(.top, 8)
            }
        }
    }
}

extension View {
    /// Add error banner handling
    func errorBanner(_ handler: CollectionErrorHandler) -> some View {
        modifier(ErrorBannerModifier(errorHandler: handler))
    }
}
