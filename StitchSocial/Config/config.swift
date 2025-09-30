//
//  Config.swift
//  StitchSocial
//
//  Layer 3: Configuration - App Configuration and Environment Settings
//  Dependencies: None - Pure configuration data
//  Features: Environment detection, API keys, Firebase settings, feature flags
//

import Foundation

/// Central configuration management for StitchSocial
/// Handles environment-specific settings, API keys, and feature flags
struct Config {
    
    // MARK: - Environment Detection
    
    enum Environment {
        case development
        case staging
        case production
        
        static var current: Environment {
            #if DEBUG
            return .development
            #elseif STAGING
            return .staging
            #else
            return .production
            #endif
        }
        
        var displayName: String {
            switch self {
            case .development: return "Development"
            case .staging: return "Staging"
            case .production: return "Production"
            }
        }
    }
    
    // MARK: - API Configuration
    
    struct API {
        /// OpenAI API Configuration
        struct OpenAI {
            static let apiKey: String = {
                // Try environment variable first
                if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                    return envKey
                }
                
                // Try Info.plist
                if let plistKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !plistKey.isEmpty {
                    return plistKey
                }
                
                // Development fallback - YOUR REAL API KEY
                switch Environment.current {
                case .development:
                    return "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"
                case .staging:
                    return "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"
                case .production:
                    return "" // Production keys should only come from secure environment variables
                }
            }()
            
            static let baseURL = "https://api.openai.com/v1"
            static let customPromptID = "pmpt_686cabe52cf88196a37bc2e947164c370e5a982b0fc4ce3a"
            static let promptVersion = "1"
            static let timeoutInterval: TimeInterval = 30.0
            static let maxRetries = 2
            static let organizationID: String? = nil // Auto-detect
            
            /// Whisper API Configuration
            struct Whisper {
                static let model = "whisper-1"
                static let responseFormat = "text"
                static let language: String? = nil // Auto-detect
            }
            
            /// Chat Completion Configuration
            struct ChatCompletion {
                static let model = "gpt-4o-mini"
                static let maxTokens = 300
                static let temperature: Double = 0.7
                static let responseFormat = "json_object"
            }
        }
    }
    
    // MARK: - Firebase Configuration
    
    struct Firebase {
        /// Database name - prevents accidental default database usage
        static let databaseName = "stitchfin"
        
        /// Storage bucket name (if different from default)
        static let storageBucket: String? = nil // Uses default
        
        /// FCM Server Key for push notifications
        static let fcmServerKey = "BIrbeI7xJ8M-BR4BRR8nVK4cgeHQ5kg7BZScN7H9OPOuPpoZCyZIT_Nxf7j5qB6fvJEKil2oXKS4ViQQ-G-ClXc"
        
        /// Firebase configuration validation
        static func validateConfiguration() -> Bool {
            guard !databaseName.isEmpty else {
                print("❌ CONFIG: Firebase database name is empty")
                return false
            }
            
            guard !fcmServerKey.isEmpty else {
                print("❌ CONFIG: FCM server key is empty")
                return false
            }
            
            print("✅ CONFIG: Firebase database configured - \(databaseName)")
            print("✅ CONFIG: FCM server key configured - \(fcmServerKey.prefix(20))...")
            return true
        }
    }
    
    // MARK: - App Configuration
    
    struct App {
        static let name = "CleanBeta"
        static let version: String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        }()
        
        static let buildNumber: String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        }()
        
        static let bundleID: String = {
            Bundle.main.bundleIdentifier ?? "com.cleanbeta.app"
        }()
        
        /// Content creation settings
        static let maxVideoLength: TimeInterval = 60.0 // 60 seconds
        static let maxVideoFileSize: Int64 = 50 * 1024 * 1024 // 50MB
        static let supportedVideoFormats = ["mp4", "mov", "m4v"]
        static let defaultVideoQuality: Float = 0.7
        
        /// Special user recognition keywords for enhanced starting conditions
        static let specialUserKeywords = [
            "founder", "ceo", "celebrity", "influencer", "partner", "topcreator", "founder", "cofounder"
        ]
        
        /// AI analysis settings
        static let analysisTimeout: TimeInterval = 30.0
        static let maxAnalysisRetries = 2
        static let progressUpdateInterval: TimeInterval = 0.1
        
        /// Content generation limits
        static let maxTitleLength = 100
        static let maxDescriptionLength = 500
        static let maxHashtags = 10
        static let maxHashtagLength = 30
        
        /// App Store configuration
        static let appStoreID = "66B6XS2SPX" // Your App Store Connect ID
        static let teamID = "66B6XS2SPX" // Your Apple Developer Team ID
    }
    
    // MARK: - Feature Flags
    
    struct Features {
        /// Enable/disable features based on environment
        static let enableAIAnalysis: Bool = {
            switch Environment.current {
            case .development: return true
            case .staging: return true
            case .production: return !API.OpenAI.apiKey.isEmpty
            }
        }()
        
        static let enableAdvancedEffects: Bool = {
            switch Environment.current {
            case .development: return true
            case .staging: return true
            case .production: return false // Enable when ready
            }
        }()
        
        static let enableDebugLogging: Bool = {
            Environment.current == .development
        }()
        
        static let enableAnalytics: Bool = {
            Environment.current == .production
        }()
        
        static let enableCrashReporting: Bool = {
            Environment.current != .development
        }()
        
        static let enablePushNotifications: Bool = {
            !Firebase.fcmServerKey.isEmpty
        }()
        
        static let enableAdvancedMetrics: Bool = {
            Environment.current == .development
        }()
    }
    
    // MARK: - Network Configuration
    
    struct Network {
        static let requestTimeout: TimeInterval = 15.0
        static let uploadTimeout: TimeInterval = 60.0
        static let maxConcurrentUploads = 3
        static let retryAttempts = 3
        static let retryDelay: TimeInterval = 1.0
    }
    
    // MARK: - Cache Configuration
    
    struct Cache {
        static let videoPreviewCacheSize: Int64 = 100 * 1024 * 1024 // 100MB
        static let imageCacheSize: Int64 = 50 * 1024 * 1024 // 50MB
        static let cacheExpirationTime: TimeInterval = 24 * 60 * 60 // 24 hours
        static let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    }
    
    // MARK: - Analytics Configuration
    
    struct Analytics {
        static let eventBatchSize = 20
        static let eventFlushInterval: TimeInterval = 30.0
        static let sessionTimeout: TimeInterval = 30 * 60 // 30 minutes
        static let maxEventRetention: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    }
    
    // MARK: - Security Configuration
    
    struct Security {
        static let enableBiometricAuth = true
        static let sessionExpiration: TimeInterval = 24 * 60 * 60 // 24 hours
        static let maxLoginAttempts = 5
        static let lockoutDuration: TimeInterval = 5 * 60 // 5 minutes
    }
    
    // MARK: - Push Notification Configuration
    
    struct PushNotifications {
        static let enableSound = true
        static let enableBadge = true
        static let enableAlert = true
        static let enableProvisional = true
        
        /// Default notification categories
        static let categories: [String] = [
            "HYPE_NOTIFICATION",
            "FOLLOW_NOTIFICATION",
            "REPLY_NOTIFICATION",
            "SYSTEM_NOTIFICATION"
        ]
    }
    
    // MARK: - Validation Methods
    
    /// Check if configuration is valid for current environment
    static func validateConfiguration() -> ConfigValidationResult {
        var issues: [String] = []
        
        // Check API keys
        if Features.enableAIAnalysis && API.OpenAI.apiKey.isEmpty {
            issues.append("OpenAI API key is missing")
        }
        
        // FIXED: Updated validation to properly handle project-based API keys
        if API.OpenAI.apiKey.hasPrefix("sk-your-") || API.OpenAI.apiKey.hasPrefix("sk-proj-your-") {
            issues.append("OpenAI API key appears to be a placeholder")
        }
        
        // Check Firebase configuration
        if !Firebase.validateConfiguration() {
            issues.append("Firebase configuration is invalid")
        }
        
        // Check app configuration
        if App.bundleID.isEmpty {
            issues.append("Bundle ID is missing")
        }
        
        // Environment-specific checks
        switch Environment.current {
        case .production:
            if Features.enableDebugLogging {
                issues.append("Debug logging should be disabled in production")
            }
            if Firebase.fcmServerKey.isEmpty {
                issues.append("FCM server key is required for production push notifications")
            }
        case .development:
            if !Features.enableDebugLogging {
                issues.append("Debug logging should be enabled in development")
            }
        case .staging:
            break // Staging can have mixed settings
        }
        
        return ConfigValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            environment: Environment.current
        )
    }
    
    /// Print configuration status for debugging
    static func printConfigurationStatus() {
        let validation = validateConfiguration()
        
        print("🔧 CONFIG STATUS:")
        print("   Environment: \(Environment.current.displayName)")
        print("   App Version: \(App.version) (\(App.buildNumber))")
        print("   AI Enabled: \(Features.enableAIAnalysis)")
        print("   OpenAI Key: \(API.OpenAI.apiKey.isEmpty ? "❌ Missing" : "✅ Configured (\(API.OpenAI.apiKey.count) chars)")")
        print("   Firebase DB: \(Firebase.databaseName)")
        print("   FCM Key: \(Firebase.fcmServerKey.isEmpty ? "❌ Missing" : "✅ Configured")")
        print("   Push Notifications: \(Features.enablePushNotifications ? "✅ Enabled" : "❌ Disabled")")
        print("   Bundle ID: \(App.bundleID)")
        print("   Debug Logging: \(Features.enableDebugLogging ? "✅" : "❌")")
        
        if !validation.isValid {
            print("   ⚠️ Issues Found:")
            for issue in validation.issues {
                print("      - \(issue)")
            }
        } else {
            print("   ✅ Configuration Valid")
        }
        
        print("FIREBASE: Configuration validated")
    }
}

// MARK: - Configuration Validation Result

/// Result of configuration validation
struct ConfigValidationResult {
    let isValid: Bool
    let issues: [String]
    let environment: Config.Environment
    
    /// Print validation summary
    func printSummary() {
        if isValid {
            print("✅ CONFIG: All validation checks passed")
        } else {
            print("❌ CONFIG: Validation failed with \(issues.count) issue(s):")
            for issue in issues {
                print("   - \(issue)")
            }
        }
    }
}
