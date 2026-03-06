//
//  VersionGateService.swift
//  StitchSocial
//
//  Created by James Garmon on 2/21/26.
//


//
//  VersionGateService.swift
//  StitchSocial
//
//  Layer 4: Core Services - App Version Gate for TestFlight / Production
//  Dependencies: FirebaseFirestore, CachingService (for TTL pattern)
//
//  HOW IT WORKS:
//  1. On app launch, reads Firestore doc: config/appVersion
//  2. Compares minimumBuild against the running CFBundleVersion
//  3. If running build < minimumBuild → publishes needsUpdate = true
//  4. StitchSocialApp shows a blocking ForceUpdateView
//
//  HOW TO TRIGGER AN UPDATE GATE:
//  1. Push new build (e.g. build 19) to TestFlight
//  2. Go to Firebase Console → Firestore → config/appVersion
//  3. Set minimumBuild to 19
//  4. All users on build 18 or lower see the update screen on next launch
//
//  CACHING:
//  - Result cached in memory for 1 hour (3600s)
//  - App foreground after cache expiry re-checks (1 read)
//  - Typical cost: 1 Firestore read per app session
//
//  FIRESTORE DOCUMENT STRUCTURE:
//  Collection: config
//  Document: appVersion
//  Fields:
//    minimumBuild: Int (e.g. 19)
//    updateMessage: String (optional, e.g. "We've added communities!")
//    testflightURL: String (your TestFlight public link)
//    forceUpdate: Bool (true = blocking, false = dismissable banner)
//

import Foundation
import FirebaseFirestore

@MainActor
class VersionGateService: ObservableObject {
    
    static let shared = VersionGateService()
    
    // MARK: - Published State
    
    @Published var needsUpdate: Bool = false
    @Published var updateMessage: String = "A new version is available with improvements and bug fixes."
    @Published var testflightURL: String = ""
    @Published var forceUpdate: Bool = true
    @Published var isChecking: Bool = false
    @Published var minimumBuild: Int = 0
    
    // MARK: - Cache
    
    private var lastCheckTime: Date?
    private let cacheTTL: TimeInterval = 3600  // 1 hour
    
    // MARK: - Current Build
    
    /// The running app's build number from Info.plist (CFBundleVersion)
    var currentBuild: Int {
        guard let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let build = Int(buildString) else {
            return 0
        }
        return build
    }
    
    /// The running app's version string (CFBundleShortVersionString)
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
    
    // MARK: - Check Version
    
    /// Call on app launch and when returning to foreground.
    /// Reads Firestore once, caches result for 1 hour.
    func checkVersion() async {
        // Skip if cache is still valid
        if let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < cacheTTL {
            print("✅ VERSION GATE: Cache valid — skipping check (build \(currentBuild))")
            return
        }
        
        isChecking = true
        defer { isChecking = false }
        
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let doc = try await db.collection("config").document("appVersion").getDocument()
            
            guard let data = doc.data() else {
                // No config doc exists yet — allow app to proceed
                print("⚠️ VERSION GATE: No config/appVersion doc found — skipping gate")
                needsUpdate = false
                lastCheckTime = Date()
                return
            }
            
            // Parse fields
            let minBuild = data["minimumBuild"] as? Int ?? 0
            let message = data["updateMessage"] as? String ?? "A new version is available with improvements and bug fixes."
            let tfURL = data["testflightURL"] as? String ?? ""
            let force = data["forceUpdate"] as? Bool ?? true
            
            minimumBuild = minBuild
            updateMessage = message
            testflightURL = tfURL
            forceUpdate = force
            lastCheckTime = Date()
            
            // Compare
            if currentBuild < minBuild {
                needsUpdate = true
                print("🚨 VERSION GATE: Update required! Running build \(currentBuild), minimum \(minBuild)")
            } else {
                needsUpdate = false
                print("✅ VERSION GATE: Build \(currentBuild) >= minimum \(minBuild) — OK")
            }
            
        } catch {
            // On error, don't block the app — fail open
            print("⚠️ VERSION GATE: Check failed — \(error.localizedDescription). Allowing app to proceed.")
            needsUpdate = false
            lastCheckTime = Date()
        }
    }
    
    /// Force re-check (ignores cache). Call after user taps "Check Again".
    func forceCheck() async {
        lastCheckTime = nil
        await checkVersion()
    }
}