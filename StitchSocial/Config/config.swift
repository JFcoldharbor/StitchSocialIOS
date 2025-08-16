//
//  Config.swift
//  CleanBeta
//
//  Created by James Garmon on 7/12/25.
//

import Foundation

/// Central configuration management for CleanBeta
/// Handles API keys, environment settings, and app configuration
/// Clean, secure approach to managing sensitive data and settings
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
                
                // Development fallback - UPDATED with your real API key
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
        
        /// Firebase configuration validation
        static func validateConfiguration() -> Bool {
            guard !databaseName.isEmpty else {
                print("❌ CONFIG: Firebase database name is empty")
                return false
            }
            
            print("✅ CONFIG: Firebase database configured - \(databaseName)")
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
    }
    
    // MARK: - Recording Configuration
    
    struct Recording {
        static let maxDuration: TimeInterval = 30.0 // 30 seconds for all users
        static let defaultAspectRatio: Double = 9.0/16.0 // Vertical video
        
        /// Quality settings by user tier
        enum VideoQuality: String, CaseIterable {
            case sd = "SD (480p)"
            case hd = "HD (720p)"
            case fullHD = "Full HD (1080p)"
            case uhd = "4K (2160p)"
            
            var sessionPreset: String {
                switch self {
                case .sd: return "AVCaptureSessionPreset640x480"
                case .hd: return "AVCaptureSessionPreset1280x720"
                case .fullHD: return "AVCaptureSessionPreset1920x1080"
                case .uhd: return "AVCaptureSessionPreset3840x2160"
                }
            }
        }
        
        /// Tier-based quality mapping
        static func videoQuality(for tier: String) -> VideoQuality {
            switch tier.lowercased() {
            case "rookie", "rising":
                return .hd
            case "influencer":
                return .fullHD
            case "partner", "topcreator", "founder", "cofounder":
                return .uhd
            default:
                return .hd
            }
        }
    }
    
    // MARK: - AI Configuration
    
    struct AI {
        /// Premium tier access for AI features
        static let premiumTiers: Set<String> = [
            "influencer", "partner", "topcreator", "founder", "cofounder"
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
    
    // MARK: - Validation Methods
    
    /// Check if configuration is valid for current environment
    static func validateConfiguration() -> ConfigValidationResult {
        var issues: [String] = []
        
        // Check API keys
        if Features.enableAIAnalysis && API.OpenAI.apiKey.isEmpty {
            issues.append("OpenAI API key is missing")
        }
        
        if API.OpenAI.apiKey.hasPrefix("sk-your-") {
            issues.append("OpenAI API key appears to be a placeholder")
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
        print("   Environment: \(Environment.current)")
        print("   App Version: \(App.version) (\(App.buildNumber))")
        print("   AI Enabled: \(Features.enableAIAnalysis)")
        print("   OpenAI Key: \(API.OpenAI.apiKey.isEmpty ? "❌ Missing" : "✅ Present")")
        print("   Debug Mode: \(Features.enableDebugLogging)")
        print("   Firebase DB: \(Firebase.databaseName)")
        
        // Validate Firebase configuration
        let firebaseValid = Firebase.validateConfiguration()
        
        if !validation.isValid || !firebaseValid {
            print("⚠️  Configuration Issues:")
            for issue in validation.issues {
                print("   - \(issue)")
            }
            if !firebaseValid {
                print("   - Firebase configuration invalid")
            }
        } else {
            print("✅ Configuration is valid")
        }
    }
}

// MARK: - Supporting Types

struct ConfigValidationResult {
    let isValid: Bool
    let issues: [String]
    let environment: Config.Environment
    
    var summary: String {
        if isValid {
            return "✅ Configuration is valid for \(environment)"
        } else {
            return "❌ Configuration has \(issues.count) issue(s) in \(environment)"
        }
    }
}

// MARK: - Environment Helpers

extension Config.Environment {
    var isDevelopment: Bool { self == .development }
    var isStaging: Bool { self == .staging }
    var isProduction: Bool { self == .production }
    
    var description: String {
        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}
