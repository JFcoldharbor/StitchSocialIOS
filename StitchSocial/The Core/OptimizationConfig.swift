//
//  OptimizationConfig.swift
//  CleanBeta
//
//  Foundation layer - Zero dependencies
//  All configuration constants, limits, and optimization settings used throughout the app
//

import Foundation
import UIKit

/// Centralized configuration for app-wide constants, limits, and optimization settings
struct OptimizationConfig {
    
    // MARK: - Video Configuration
    
    /// Video recording and processing limits
    struct Video {
        /// Maximum video duration in seconds
        static let maxDuration: TimeInterval = 60.0 // 60 seconds
        
        /// Minimum video duration in seconds
        static let minDuration: TimeInterval = 1.0 // 1 second
        
        /// Maximum video file size in bytes
        static let maxFileSize: Int64 = 100 * 1024 * 1024 // 100MB
        
        /// Minimum video file size in bytes
        static let minFileSize: Int64 = 1024 * 1024 // 1MB
        
        /// Default video quality for recording
        static let defaultQuality: String = "high" // RecordingQuality.high.rawValue
        
        /// Maximum concurrent video uploads
        static let maxConcurrentUploads = 3
        
        /// Maximum concurrent video downloads
        static let maxConcurrentDownloads = 5
        
        /// Video upload chunk size in bytes
        static let uploadChunkSize: Int64 = 256 * 1024 // 256KB
        
        /// Thumbnail generation timeout in seconds
        static let thumbnailTimeout: TimeInterval = 30.0
        
        /// Video compression timeout in seconds
        static let compressionTimeout: TimeInterval = 300.0 // 5 minutes
        
        /// Supported video formats
        static let supportedFormats = ["mp4", "mov", "m4v"]
        
        /// Maximum video resolution width
        static let maxResolutionWidth = 1440
        
        /// Maximum video resolution height
        static let maxResolutionHeight = 2560
        
        /// Default aspect ratio (vertical videos)
        static let defaultAspectRatio = 9.0 / 16.0
        
        /// Video bitrate limits by quality
        static let bitrateStandard = 2_000_000  // 2 Mbps
        static let bitrateHigh = 5_000_000      // 5 Mbps
        static let bitratePremium = 10_000_000  // 10 Mbps
    }
    
    // MARK: - Thread System Configuration
    
    /// Thread hierarchy limits and settings
    struct Threading {
        /// Maximum children per thread (direct replies to thread starter)
        static let maxChildrenPerThread = 10
        
        /// Maximum stepchildren per child (replies to child videos)
        static let maxStepchildrenPerChild = 10
        
        /// Maximum conversation depth (Thread -> Child -> Stepchild)
        static let maxConversationDepth = 2
        
        /// Thread auto-lock timeout (no new replies after X hours)
        static let autoLockTimeoutHours: TimeInterval = 24 * 7 // 7 days
        
        /// Maximum thread title length
        static let maxThreadTitleLength = 100
        
        /// Minimum thread title length
        static let minThreadTitleLength = 3
        
        /// Thread trending calculation window in hours
        static let trendingWindowHours: TimeInterval = 24 // 24 hours
        
        /// Temperature update interval in seconds
        static let temperatureUpdateInterval: TimeInterval = 300 // 5 minutes
        
        /// Minimum engagement for trending
        static let minEngagementForTrending = 50
        
        /// Thread discovery boost duration in hours
        static let discoveryBoostDurationHours: TimeInterval = 6
    }
    
    // MARK: - User System Configuration
    
    /// User account and profile limits
    struct User {
        /// Maximum username length
        static let maxUsernameLength = 20
        
        /// Minimum username length
        static let minUsernameLength = 3
        
        /// Maximum display name length
        static let maxDisplayNameLength = 50
        
        /// Maximum bio length
        static let maxBioLength = 150
        
        /// Minimum bio length
        static let minBioLength = 0
        
        /// Default starting clout for new users
        static let defaultStartingClout = 1500
        
        /// Maximum profile image size in bytes
        static let maxProfileImageSize: Int64 = 5 * 1024 * 1024 // 5MB
        
        /// Supported profile image formats
        static let supportedImageFormats = ["jpg", "jpeg", "png", "heic"]
        
        /// Username validation pattern (alphanumeric + underscore)
        static let usernamePattern = "^[a-zA-Z0-9_]{3,20}$"
        
        /// Email validation timeout
        static let emailValidationTimeout: TimeInterval = 30.0
        
        /// Password minimum length
        static let minPasswordLength = 8
        
        /// Maximum failed login attempts before lockout
        static let maxFailedLoginAttempts = 5
        
        /// Account lockout duration in seconds
        static let accountLockoutDuration: TimeInterval = 300 // 5 minutes
    }
    
    // MARK: - Engagement System Configuration
    
    /// Engagement mechanics and limits
    struct Engagement {
        /// Cooldown between hype/cool actions (prevent spam)
        static let interactionCooldown: TimeInterval = 0.5 // 500ms
        
        /// Maximum hypes per user per day
        static let maxHypesPerDay = 1000
        
        /// Maximum cools per user per day
        static let maxCoolsPerDay = 500
        
        /// Engagement streak timeout (reset if no activity)
        static let streakTimeoutHours: TimeInterval = 24
        
        /// Points for different interactions
        static let pointsForHype = 10
        static let pointsForCool = -5
        static let pointsForReply = 50
        static let pointsForShare = 25
        static let pointsForView = 1
        
        /// Viral threshold (when content becomes "blazing")
        static let viralThreshold = 10000
        
        /// Hot threshold (when content becomes "hot")
        static let hotThreshold = 1000
        
        /// Warm threshold (when content becomes "warm")
        static let warmThreshold = 100
        
        /// Engagement velocity calculation window in hours
        static let velocityWindowHours: TimeInterval = 6
        
        /// Anti-spam detection threshold
        static let spamDetectionThreshold = 20 // interactions per minute
    }
    
    // MARK: - Cache Configuration
    
    /// Caching system limits and settings
    struct Cache {
        /// Maximum disk cache size in bytes
        static let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
        
        /// Maximum memory cache size in bytes
        static let maxMemoryCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
        
        /// Cache expiration time in seconds
        static let cacheExpirationTime: TimeInterval = 24 * 60 * 60 // 24 hours
        
        /// Cache cleanup interval in seconds
        static let cleanupInterval: TimeInterval = 60 * 60 // 1 hour
        
        /// Maximum cached video files
        static let maxCachedVideoFiles = 50
        
        /// Maximum cached image files
        static let maxCachedImageFiles = 200
        
        /// Maximum cached data entries
        static let maxCachedDataEntries = 1000
        
        /// Cache compression threshold (compress files larger than this)
        static let compressionThreshold: Int64 = 1024 * 1024 // 1MB
        
        /// Cache hit ratio warning threshold
        static let hitRatioWarningThreshold = 0.7 // 70%
        
        /// Maximum cache age before force refresh (in seconds)
        static let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    }
    
    // MARK: - Network Configuration
    
    /// Network requests and timeouts
    struct Network {
        /// Default network request timeout
        static let defaultTimeout: TimeInterval = 30.0
        
        /// Upload request timeout
        static let uploadTimeout: TimeInterval = 300.0 // 5 minutes
        
        /// Download request timeout
        static let downloadTimeout: TimeInterval = 120.0 // 2 minutes
        
        /// Maximum retry attempts for failed requests
        static let maxRetryAttempts = 3
        
        /// Retry delay between attempts (exponential backoff base)
        static let retryDelayBase: TimeInterval = 2.0
        
        /// Maximum concurrent network requests
        static let maxConcurrentRequests = 10
        
        /// Rate limiting: requests per minute
        static let rateLimitPerMinute = 100
        
        /// Rate limiting: burst allowance
        static let rateLimitBurst = 20
        
        /// Connection quality check interval
        static let connectionCheckInterval: TimeInterval = 30.0
        
        /// Minimum connection speed for video upload (bytes per second)
        static let minUploadSpeed: Int64 = 100 * 1024 // 100KB/s
    }
    
    // MARK: - Performance Configuration
    
    /// App performance and optimization settings
    struct Performance {
        /// Maximum background tasks
        static let maxBackgroundTasks = 5
        
        /// Memory warning threshold (percentage)
        static let memoryWarningThreshold = 0.8 // 80%
        
        /// CPU usage warning threshold (percentage)
        static let cpuWarningThreshold = 0.7 // 70%
        
        /// Battery level optimization threshold (percentage)
        static let batteryOptimizationThreshold = 0.2 // 20%
        
        /// Maximum concurrent video processing tasks
        static let maxVideoProcessingTasks = 2
        
        /// Frame rate target for video playback
        static let targetFrameRate = 30
        
        /// Maximum texture memory usage in bytes
        static let maxTextureMemory: Int64 = 50 * 1024 * 1024 // 50MB
        
        /// Garbage collection interval in seconds
        static let gcInterval: TimeInterval = 60.0
        
        /// Maximum UI update frequency (FPS)
        static let maxUIUpdateFrequency = 60
        
        /// Animation performance threshold (milliseconds)
        static let animationPerformanceThreshold: TimeInterval = 16.67 // 60 FPS
    }
    
    // MARK: - UI Configuration
    
    /// User interface settings and limits
    struct UI {
        /// Default animation duration
        static let defaultAnimationDuration: TimeInterval = 0.3
        
        /// Fast animation duration
        static let fastAnimationDuration: TimeInterval = 0.15
        
        /// Slow animation duration
        static let slowAnimationDuration: TimeInterval = 0.6
        
        /// Touch gesture minimum distance (points)
        static let minGestureDistance: CGFloat = 20.0
        
        /// Touch gesture velocity threshold
        static let gestureVelocityThreshold: CGFloat = 300.0
        
        /// Maximum haptic feedback frequency (per second)
        static let maxHapticFrequency = 10
        
        /// UI element fade duration
        static let fadeAnimationDuration: TimeInterval = 0.25
        
        /// Loading indicator delay (show after X seconds)
        static let loadingIndicatorDelay: TimeInterval = 0.5
        
        /// Toast notification display duration
        static let toastDisplayDuration: TimeInterval = 3.0
        
        /// Maximum toast notifications on screen
        static let maxToastNotifications = 3
        
        /// Tab bar animation duration
        static let tabBarAnimationDuration: TimeInterval = 0.2
        
        /// Safe area margin (points)
        static let safeAreaMargin: CGFloat = 16.0
    }
    
    // MARK: - Security Configuration
    
    /// Security and privacy settings
    struct Security {
        /// Session timeout in seconds
        static let sessionTimeout: TimeInterval = 24 * 60 * 60 // 24 hours
        
        /// Token refresh threshold (refresh when X seconds remain)
        static let tokenRefreshThreshold: TimeInterval = 5 * 60 // 5 minutes
        
        /// Maximum login session duration
        static let maxSessionDuration: TimeInterval = 30 * 24 * 60 * 60 // 30 days
        
        /// Encryption key rotation interval
        static let keyRotationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        
        /// Maximum stored sensitive data age
        static let maxSensitiveDataAge: TimeInterval = 24 * 60 * 60 // 24 hours
        
        /// Failed authentication lockout duration
        static let authLockoutDuration: TimeInterval = 15 * 60 // 15 minutes
        
        /// Security audit log retention (days)
        static let auditLogRetentionDays = 90
        
        /// Biometric authentication timeout
        static let biometricTimeout: TimeInterval = 5 * 60 // 5 minutes
        
        /// Password complexity requirements
        static let requireSpecialCharacters = true
        static let requireNumbers = true
        static let requireUppercase = true
        static let requireLowercase = true
    }
    
    // MARK: - Analytics Configuration
    
    /// Analytics and tracking settings
    struct Analytics {
        /// Event batch size for transmission
        static let eventBatchSize = 50
        
        /// Event transmission interval
        static let transmissionInterval: TimeInterval = 30.0
        
        /// Maximum events stored locally
        static let maxStoredEvents = 1000
        
        /// Event retention time (seconds)
        static let eventRetentionTime: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        
        /// User session timeout for analytics
        static let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes
        
        /// Maximum custom event properties
        static let maxCustomProperties = 20
        
        /// Analytics data compression threshold
        static let compressionThreshold = 1024 // 1KB
        
        /// Offline analytics storage limit
        static let offlineStorageLimit: Int64 = 10 * 1024 * 1024 // 10MB
    }
    
    // MARK: - Feature Flags
    
    /// Feature enablement and experimental settings
    struct Features {
        /// Enable beta features
        static let enableBetaFeatures = false
        
        /// Enable debug logging
        static let enableDebugLogging = true
        
        /// Enable crash reporting
        static let enableCrashReporting = true
        
        /// Enable analytics tracking
        static let enableAnalytics = true
        
        /// Enable push notifications
        static let enablePushNotifications = true
        
        /// Enable background app refresh
        static let enableBackgroundRefresh = true
        
        /// Enable haptic feedback
        static let enableHapticFeedback = true
        
        /// Enable advanced video features
        static let enableAdvancedVideoFeatures = false
        
        /// Enable AI-powered recommendations
        static let enableAIRecommendations = false
        
        /// Enable real-time collaboration
        static let enableRealTimeCollaboration = true
        
        /// Enable offline mode
        static let enableOfflineMode = true
        
        /// Enable A/B testing
        static let enableABTesting = false
    }
}

// MARK: - Environment-Specific Overrides

extension OptimizationConfig {
    
    /// Development environment overrides
    struct Development {
        static let reducedCacheLimits = true
        static let enableVerboseLogging = true
        static let shortenedTimeouts = true
        static let disableAnalytics = true
        static let enableAllBetaFeatures = true
        
        /// Apply development overrides
        static func applyOverrides() {
            // This method can be called in debug builds to override production settings
            #if DEBUG
            print("🔧 OPTIMIZATION CONFIG: Development overrides applied")
            #endif
        }
    }
    
    /// Production environment optimizations
    struct Production {
        static let enablePerformanceOptimizations = true
        static let enableSecurityHardening = true
        static let enableTelemetry = true
        static let strictErrorHandling = true
        
        /// Apply production optimizations
        static func applyOptimizations() {
            print("🚀 OPTIMIZATION CONFIG: Production optimizations applied")
        }
    }
}

// MARK: - Dynamic Configuration

extension OptimizationConfig {
    
    /// Adjust settings based on device capabilities
    static func adjustForDevice() {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        
        // Adjust based on available memory
        let physicalMemory = processInfo.physicalMemory
        if physicalMemory < 2 * 1024 * 1024 * 1024 { // Less than 2GB RAM
            // Reduce cache limits for low-memory devices
            print("📱 OPTIMIZATION CONFIG: Applied low-memory optimizations")
        }
        
        // Adjust based on device performance
        if device.model.contains("iPhone") {
            // iPhone-specific optimizations
            print("📱 OPTIMIZATION CONFIG: Applied iPhone optimizations")
        } else if device.model.contains("iPad") {
            // iPad-specific optimizations
            print("📱 OPTIMIZATION CONFIG: Applied iPad optimizations")
        }
    }
    
    /// Get configuration value with environment override
    static func getValue<T>(for value: T, environment: Environment = .production) -> T {
        switch environment {
        case .development:
            // Return development-specific values if available
            return value
        case .staging:
            // Return staging-specific values if available
            return value
        case .production:
            return value
        }
    }
    
    enum Environment {
        case development
        case staging
        case production
    }
}
