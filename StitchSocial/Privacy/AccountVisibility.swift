//
//  AccountVisibility.swift
//  StitchSocial
//
//  Created by James Garmon on 2/17/26.
//


//
//  PrivacySettings.swift
//  StitchSocial
//
//  Layer 1: Foundation - Privacy & Visibility Types
//  Dependencies: None (pure Swift types)
//  Features: Account visibility, discoverability, content visibility, age gating
//

import Foundation

// MARK: - Account Visibility

/// Who can see the user's profile
enum AccountVisibility: String, Codable, CaseIterable {
    case `public` = "public"       // Anyone
    case followers = "followers"   // Only followers
}

// MARK: - Discoverability Mode

/// Whether user's threads appear in Discovery feed
enum DiscoverabilityMode: String, Codable, CaseIterable {
    case `public` = "public"       // Appears in Discovery for everyone
    case followers = "followers"   // Only appears in followers' feeds
    case none = "none"             // Never appears in Discovery
}

// MARK: - Content Visibility

/// Per-video visibility setting
enum ContentVisibility: String, Codable, CaseIterable {
    case `public` = "public"       // Anyone can see
    case followers = "followers"   // Only creator's followers
    case tagged = "tagged"         // Only tagged users + creator
    case `private` = "private"     // Only creator
    
    var displayName: String {
        switch self {
        case .public: return "Public"
        case .followers: return "Followers Only"
        case .tagged: return "Tagged People Only"
        case .private: return "Private"
        }
    }
    
    var icon: String {
        switch self {
        case .public: return "globe"
        case .followers: return "person.2.fill"
        case .tagged: return "tag.fill"
        case .private: return "lock.fill"
        }
    }
}

// MARK: - Age Group

/// Age-based content routing
enum AgeGroup: String, Codable, CaseIterable {
    case teen = "teen"
    case adult = "adult"
    
    /// Storage bucket for this age group
    var storageBucket: String {
        switch self {
        case .teen: return "gs://stitchbeta-8bbfe-teen"
        case .adult: return "gs://stitchbeta-8bbfe.firebasestorage.app"
        }
    }
}

// MARK: - User Privacy Settings

/// Maps to `privacySettings` field on user document
struct UserPrivacySettings: Codable {
    var accountVisibility: AccountVisibility
    var discoverabilityMode: DiscoverabilityMode
    var defaultStitchVisibility: ContentVisibility
    var ageGroup: AgeGroup
    var ageVerifiedAt: Date?
    
    static let `default` = UserPrivacySettings(
        accountVisibility: .public,
        discoverabilityMode: .public,
        defaultStitchVisibility: .public,
        ageGroup: .adult,
        ageVerifiedAt: nil
    )
    
    /// Convert to Firestore map
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "accountVisibility": accountVisibility.rawValue,
            "discoverabilityMode": discoverabilityMode.rawValue,
            "defaultStitchVisibility": defaultStitchVisibility.rawValue,
            "ageGroup": ageGroup.rawValue
        ]
        if let verified = ageVerifiedAt {
            data["ageVerifiedAt"] = verified
        }
        return data
    }
    
    /// Parse from Firestore map
    static func from(firestoreMap: [String: Any]?) -> UserPrivacySettings {
        guard let map = firestoreMap else { return .default }
        return UserPrivacySettings(
            accountVisibility: AccountVisibility(rawValue: map["accountVisibility"] as? String ?? "") ?? .public,
            discoverabilityMode: DiscoverabilityMode(rawValue: map["discoverabilityMode"] as? String ?? "") ?? .public,
            defaultStitchVisibility: ContentVisibility(rawValue: map["defaultStitchVisibility"] as? String ?? "") ?? .public,
            ageGroup: AgeGroup(rawValue: map["ageGroup"] as? String ?? "") ?? .adult,
            ageVerifiedAt: map["ageVerifiedAt"] as? Date
        )
    }
}

// MARK: - Video Privacy Fields

/// Additional fields written to video document at upload time
struct VideoPrivacyFields: Codable {
    var visibility: ContentVisibility
    var allowedViewerIDs: [String]   // Populated when visibility == .tagged
    var excludeFromDiscovery: Bool
    var teenSafe: Bool               // Flagged for teen bucket content
    
    static func forUpload(
        creatorPrivacy: UserPrivacySettings,
        taggedUserIDs: [String],
        creatorID: String,
        overrideVisibility: ContentVisibility? = nil
    ) -> VideoPrivacyFields {
        let visibility = overrideVisibility ?? creatorPrivacy.defaultStitchVisibility
        
        // Build allowed viewer list for tagged-only content
        var allowedViewers: [String] = []
        if visibility == .tagged {
            allowedViewers = Array(Set(taggedUserIDs + [creatorID]))
        }
        
        // Exclude from discovery if not public or creator opted out
        let excludeFromDiscovery = visibility != .public
            || creatorPrivacy.discoverabilityMode == .none
        
        return VideoPrivacyFields(
            visibility: visibility,
            allowedViewerIDs: allowedViewers,
            excludeFromDiscovery: excludeFromDiscovery,
            teenSafe: creatorPrivacy.ageGroup == .teen
        )
    }
    
    /// Convert to Firestore fields (merged into video document)
    var firestoreData: [String: Any] {
        return [
            "visibility": visibility.rawValue,
            "allowedViewerIDs": allowedViewerIDs,
            "excludeFromDiscovery": excludeFromDiscovery,
            "teenSafe": teenSafe
        ]
    }
    
    /// Parse from Firestore video document
    static func from(firestoreData: [String: Any]) -> VideoPrivacyFields {
        return VideoPrivacyFields(
            visibility: ContentVisibility(rawValue: firestoreData["visibility"] as? String ?? "") ?? .public,
            allowedViewerIDs: firestoreData["allowedViewerIDs"] as? [String] ?? [],
            excludeFromDiscovery: firestoreData["excludeFromDiscovery"] as? Bool ?? false,
            teenSafe: firestoreData["teenSafe"] as? Bool ?? false
        )
    }
}

// MARK: - Firestore Schema Constants

extension FirebaseSchema {
    struct PrivacyFields {
        // User document fields (inside privacySettings map)
        static let privacySettings = "privacySettings"
        static let accountVisibility = "accountVisibility"
        static let discoverabilityMode = "discoverabilityMode"
        static let defaultStitchVisibility = "defaultStitchVisibility"
        static let ageGroup = "ageGroup"
        static let ageVerifiedAt = "ageVerifiedAt"
        
        // Video document fields (top-level)
        static let visibility = "visibility"
        static let allowedViewerIDs = "allowedViewerIDs"
        static let excludeFromDiscovery = "excludeFromDiscovery"
        static let teenSafe = "teenSafe"
    }
}