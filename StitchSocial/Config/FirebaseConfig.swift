import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebasePerformance
import FirebaseDatabase
import FirebaseAnalytics
import FirebaseCrashlytics

/// Centralized Firebase configuration and initialization
/// Integrates with Config.swift for environment-specific settings
class FirebaseConfig {
    static let shared = FirebaseConfig()
    
    private init() {}
    
    /// Configure Firebase with all necessary SDKs
    func configure() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure Firestore with named database
        configureFirestore()
        
        // Configure Realtime Database
        configureRealtimeDatabase()
        
        // Configure Performance Monitoring
        configurePerformance()
        
        // Configure Analytics (respects Config feature flags)
        if Config.Features.enableAnalytics {
            Analytics.setAnalyticsCollectionEnabled(true)
        }
        
        // Configure Crashlytics (respects Config feature flags)
        if Config.Features.enableCrashReporting {
            configureCrashlytics()
        }
        
        // Validate Firebase configuration
        if !Config.Firebase.validateConfiguration() {
            #if DEBUG
            print("⚠️ FIREBASE: Configuration validation failed")
            #endif
        }
        
        if Config.Features.enableDebugLogging {
            #if DEBUG
            print("✅ FIREBASE: All services configured successfully")
            #endif
            #if DEBUG
            print("   Database: \(Config.Firebase.databaseName)")
            #endif
            #if DEBUG
            print("   Analytics: \(Config.Features.enableAnalytics ? "Enabled" : "Disabled")")
            #endif
            #if DEBUG
            print("   Crashlytics: \(Config.Features.enableCrashReporting ? "Enabled" : "Disabled")")
            #endif
            #if DEBUG
            print("   Performance: Enabled")
            #endif
            #if DEBUG
            print("   Realtime DB: Enabled")
            #endif
        }
    }
    
    // MARK: - Firestore Configuration
    
    private func configureFirestore() {
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
        
        // Use named database from Config
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        db.settings = settings
        
        if Config.Features.enableDebugLogging {
            #if DEBUG
            print("✅ FIRESTORE: Configured with database '\(Config.Firebase.databaseName)'")
            #endif
        }
    }
    
    // MARK: - Realtime Database Configuration
    
    private func configureRealtimeDatabase() {
        // CRITICAL: Set persistence BEFORE accessing any database reference
        Database.database().isPersistenceEnabled = true
        
        // Set cache size (100MB)
        Database.database().persistenceCacheSizeBytes = 100 * 1024 * 1024
        
        // Now we can safely get a reference to verify
        let _ = Database.database().reference()
        
        if Config.Features.enableDebugLogging {
            #if DEBUG
            print("✅ REALTIME DB: Configured with persistence enabled")
            #endif
        }
    }
    
    // MARK: - Performance Monitoring Configuration
    
    private func configurePerformance() {
        // Performance SDK is automatically initialized
        // Enable/disable based on environment
        let isEnabled = Config.Environment.current != .development || Config.Features.enableAdvancedMetrics
        Performance.sharedInstance().isDataCollectionEnabled = isEnabled
        Performance.sharedInstance().isInstrumentationEnabled = isEnabled
        
        if Config.Features.enableDebugLogging {
            #if DEBUG
            print("✅ PERFORMANCE: Monitoring \(isEnabled ? "enabled" : "disabled")")
            #endif
        }
    }
    
    // MARK: - Crashlytics Configuration
    
    private func configureCrashlytics() {
        // Crashlytics is automatically initialized
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        // Set user identifier for better crash tracking
        if let userId = Auth.auth().currentUser?.uid {
            Crashlytics.crashlytics().setUserID(userId)
        }
        
        if Config.Features.enableDebugLogging {
            #if DEBUG
            print("✅ CRASHLYTICS: Configured and enabled")
            #endif
        }
    }
    
    // MARK: - Helper Methods
    
    /// Get Firestore instance (named database)
    static var firestore: Firestore {
        return Firestore.firestore(database: Config.Firebase.databaseName)
    }
    
    /// Get Realtime Database reference
    static var realtimeDatabase: DatabaseReference {
        return Database.database().reference()
    }
    
    /// Get Storage reference
    static var storage: Storage {
        return Storage.storage()
    }
}
