//
//  BusinessProfile.swift
//  StitchSocial
//
//  Business account model and profile fields.
//  Dependencies: AccountType (AdRevenueShare.swift), AdCategory (AdRevenueShare.swift)
//
//  Business accounts are locked at signup — no switching to/from personal.
//  Existing companies migrated via admin Firestore backfill.
//
//  Business profiles do NOT show: follower count, following count, tier badge,
//  clout score, community, subscriber count, or any social metrics.
//
//  Business profiles DO show: brand name, website, category, logo,
//  active campaigns, and promoted content.
//
//  CACHING NOTE: Business profile data cached alongside user data in
//  CachingService.userCache. No separate cache needed — same TTL as user lookups.
//

import Foundation
import FirebaseFirestore

// MARK: - Business Profile Data

/// Additional fields stored on the user doc for business accounts.
/// Firestore: users/{userID} — these fields only exist when accountType == "business"
struct BusinessProfile: Codable, Hashable {
    let brandName: String
    let websiteURL: String?
    let businessCategory: AdCategory
    let brandLogoURL: String?
    let businessDescription: String?
    let isVerifiedBusiness: Bool
    let createdAt: Date
    
    /// Display-friendly category label
    var categoryDisplay: String {
        "\(businessCategory.icon) \(businessCategory.displayName)"
    }
}

// MARK: - Business Profile Builder

/// Extracts BusinessProfile from a user document's raw Firestore data.
/// Returns nil if accountType is not "business" or fields are missing.
/// NOTE: FirebaseSchema.UserDocument business fields defined in FirebaseSchema.swift
enum BusinessProfileBuilder {
    
    static func build(from data: [String: Any]) -> BusinessProfile? {
        guard let accountType = data[FirebaseSchema.UserDocument.accountType] as? String,
              accountType == AccountType.business.rawValue,
              let brandName = data[FirebaseSchema.UserDocument.brandName] as? String else {
            return nil
        }
        
        // Fuzzy category match: handles "real estate" vs "real_estate", case mismatches
        let categoryRaw = data[FirebaseSchema.UserDocument.businessCategory] as? String ?? "other"
        let normalizedCategory = categoryRaw.lowercased().replacingOccurrences(of: " ", with: "_")
        let category = AdCategory(rawValue: normalizedCategory) ?? .other
        
        let websiteURL = data[FirebaseSchema.UserDocument.websiteURL] as? String
        let brandLogoURL = data[FirebaseSchema.UserDocument.brandLogoURL] as? String
        let businessDescription = data[FirebaseSchema.UserDocument.businessDescription] as? String
        let isVerified = data[FirebaseSchema.UserDocument.isVerifiedBusiness] as? Bool ?? false
        let createdAt = (data[FirebaseSchema.UserDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
        
        return BusinessProfile(
            brandName: brandName,
            websiteURL: websiteURL,
            businessCategory: category,
            brandLogoURL: brandLogoURL,
            businessDescription: businessDescription,
            isVerifiedBusiness: isVerified,
            createdAt: createdAt
        )
    }
}

// MARK: - Admin Migration Helper

/// One-time admin backfill for converting existing personal accounts to business.
/// Run from admin panel or Firestore console script.
///
/// Usage:
///   try await BusinessMigration.migrateToBusinessAccount(
///       userID: "abc123",
///       brandName: "Nike",
///       websiteURL: "https://nike.com",
///       businessCategory: .fitness
///   )
///
/// What it does:
///   1. Sets accountType to "business"
///   2. Writes business-specific fields
///   3. Zeroes out followerCount/followingCount (clean slate)
///   4. Sets tier to .rookie (business accounts don't use tiers)
///   5. Clears clout, community, subscription data
///
/// IMPORTANT: This is destructive for the old personal account data.
/// Only run on accounts confirmed as businesses.
enum BusinessMigration {
    
    private static let db = Firestore.firestore()
    
    static func migrateToBusinessAccount(
        userID: String,
        brandName: String,
        websiteURL: String? = nil,
        businessCategory: AdCategory,
        businessDescription: String? = nil
    ) async throws {
        
        let userRef = db.collection(FirebaseSchema.Collections.users).document(userID)
        
        // Verify user exists and is currently personal
        let doc = try await userRef.getDocument()
        guard let data = doc.data() else {
            throw BusinessMigrationError.userNotFound
        }
        
        let currentAccountType = data[FirebaseSchema.UserDocument.accountType] as? String ?? "personal"
        guard currentAccountType == "personal" else {
            throw BusinessMigrationError.alreadyBusiness
        }
        
        // Atomic update — all fields at once
        let updates: [String: Any] = [
            FirebaseSchema.UserDocument.accountType: AccountType.business.rawValue,
            FirebaseSchema.UserDocument.brandName: brandName,
            FirebaseSchema.UserDocument.websiteURL: websiteURL as Any,
            FirebaseSchema.UserDocument.businessCategory: businessCategory.rawValue,
            FirebaseSchema.UserDocument.businessDescription: businessDescription as Any,
            FirebaseSchema.UserDocument.isVerifiedBusiness: false,
            FirebaseSchema.UserDocument.displayName: brandName,
            // Zero out social metrics — business accounts don't show these
            FirebaseSchema.UserDocument.followerCount: 0,
            FirebaseSchema.UserDocument.followingCount: 0,
            FirebaseSchema.UserDocument.clout: 0,
            FirebaseSchema.UserDocument.tier: UserTier.rookie.rawValue,
            FirebaseSchema.UserDocument.updatedAt: Timestamp()
        ]
        
        try await userRef.updateData(updates)
        
        print("🏢 MIGRATION: Converted \(userID) to business account: \(brandName)")
    }
    
    /// Batch migrate multiple accounts at once.
    /// Each entry is (userID, brandName, websiteURL?, category).
    static func batchMigrate(
        accounts: [(userID: String, brandName: String, websiteURL: String?, category: AdCategory)]
    ) async throws -> (success: Int, failed: Int) {
        var successCount = 0
        var failCount = 0
        
        for account in accounts {
            do {
                try await migrateToBusinessAccount(
                    userID: account.userID,
                    brandName: account.brandName,
                    websiteURL: account.websiteURL,
                    businessCategory: account.category
                )
                successCount += 1
            } catch {
                print("⚠️ MIGRATION: Failed for \(account.userID): \(error.localizedDescription)")
                failCount += 1
            }
        }
        
        print("🏢 MIGRATION: Batch complete — \(successCount) success, \(failCount) failed")
        return (successCount, failCount)
    }
}

// MARK: - Migration Errors

enum BusinessMigrationError: LocalizedError {
    case userNotFound
    case alreadyBusiness
    case hasActiveSubscribers
    case hasActiveCommunity
    
    var errorDescription: String? {
        switch self {
        case .userNotFound: return "User not found"
        case .alreadyBusiness: return "Account is already a business account"
        case .hasActiveSubscribers: return "Cannot migrate — account has active subscribers"
        case .hasActiveCommunity: return "Cannot migrate — account has an active community"
        }
    }
}

// MARK: - BasicUserInfo Extension

/// Adds accountType and businessProfile to the existing user model.
// MARK: - Profile View Switching Logic

/// Determines which profile layout to show based on account type.
/// Used by ProfileView to swap between personal and business layouts.
enum ProfileViewMode {
    case personal    // Full social profile: tier, clout, followers, community, subs
    case business    // Brand profile: brand name, website, category, campaigns
    
    /// Determine mode from user data
    static func resolve(accountType: AccountType) -> ProfileViewMode {
        switch accountType {
        case .personal: return .personal
        case .business: return .business
        }
    }
    
    /// Fields hidden on business profiles
    static let hiddenOnBusiness: Set<String> = [
        "followerCount",
        "followingCount",
        "tier",
        "clout",
        "communityButton",
        "subscriberCount",
        "subscribeButton",
        "adRevenueSection"
    ]
    
    /// Fields shown only on business profiles
    static let businessOnlyFields: Set<String> = [
        "brandName",
        "websiteURL",
        "businessCategory",
        "activeCampaigns",
        "promotedContent",
        "businessAnalytics"
    ]
}
