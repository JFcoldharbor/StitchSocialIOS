//
//  ReferralService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Referral System Implementation
//  Dependencies: FirebaseSchema (Layer 3), UserTier (Layer 1)
//  Features: Code generation, link sharing, reward tracking, fraud prevention
//
//  UPDATED: Auto-follow referrer on successful referral redemption
//  UPDATED: Organic signup tracking for complete timeline
//  BATCHING: processReferralSignup uses single transaction for all 5 writes
//           (referral doc + referrer stats + new user update + 2 follow subcollection docs)
//           This saves 4 extra round trips vs individual writes
//

import Foundation
import Firebase
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Referral Data Models

/// Referral status tracking
enum ReferralStatus: String, CaseIterable {
    case pending = "pending"
    case completed = "completed"
    case expired = "expired"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .expired: return "Expired"
        case .failed: return "Failed"
        }
    }
}

/// Referral source tracking
enum ReferralSourceType: String, CaseIterable {
    case link = "link"
    case deeplink = "deeplink"
    case manual = "manual"
    case share = "share"
    case organic = "organic"  // No referral code — direct signup
}

struct ReferralStats {
    let totalReferrals: Int
    let completedReferrals: Int
    let pendingReferrals: Int
    let cloutEarned: Int
    let hypeRatingBonus: Double
    let rewardsMaxed: Bool
    let referralCode: String
    let referralLink: String
    let monthlyReferrals: Int
    let recentReferrals: [ReferralInfo]
}

/// Individual referral information
struct ReferralInfo {
    let id: String
    let refereeID: String?
    let refereeUsername: String?
    let status: ReferralStatus
    let createdAt: Date
    let completedAt: Date?
    let cloutAwarded: Int
    let platform: String
    let sourceType: ReferralSourceType
}

/// Referral link generation result
struct ReferralLink {
    let code: String
    let universalLink: String
    let deepLink: String
    let shareText: String
    let expiresAt: Date
}

/// Referral processing result
struct ReferralProcessingResult {
    let success: Bool
    let referralID: String?
    let cloutAwarded: Int
    let hypeBonus: Double
    let rewardsMaxed: Bool
    let message: String
    let error: String?
    let referrerID: String?  // NEW: returned so caller knows who was followed
}

// MARK: - Referral Service

/// Complete referral system service for viral user acquisition
@MainActor
class ReferralService: ObservableObject {
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: "stitchfin")
    
    // MARK: - State
    
    @Published var userStats: ReferralStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Constants
    
    private let cloutPerReferral = 100
    private let maxCloutFromReferrals = 1000
    private let hypeRatingBonusPerReferral = 0.001 // 0.10%
    private let referralExpirationDays = 30
    private let baseURL = "https://stitchsocial.app"
    private let deepLinkScheme = "stitchsocial"
    
    // MARK: - Public Interface
    
    /// Generate or retrieve user's referral code and link
    func generateReferralLink(for userID: String) async throws -> ReferralLink {
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        guard userDoc.exists else {
            throw NSError(domain: "ReferralService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let existingCode = userDoc.data()?[FirebaseSchema.UserDocument.referralCode] as? String
        
        let referralCode: String
        if let existing = existingCode, !existing.isEmpty {
            referralCode = existing
        } else {
            referralCode = try await generateUniqueReferralCode()
            
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .updateData([
                    FirebaseSchema.UserDocument.referralCode: referralCode,
                    FirebaseSchema.UserDocument.referralCreatedAt: Timestamp()
                ])
        }
        
        let universalLink = "\(baseURL)/invite/\(referralCode)"
        let deepLink = "\(deepLinkScheme)://invite/\(referralCode)"
        let shareText = generateShareText(referralCode: referralCode)
        let expiresAt = Date().addingTimeInterval(TimeInterval(referralExpirationDays * 24 * 60 * 60))
        
        return ReferralLink(
            code: referralCode,
            universalLink: universalLink,
            deepLink: deepLink,
            shareText: shareText,
            expiresAt: expiresAt
        )
    }
    
    // MARK: - Process Referral Signup (with Auto-Follow)
    
    /// Process referral code at signup — validates, awards, AND auto-follows referrer
    /// BATCHING: Single Firestore transaction for all writes (referral doc + stats + follow docs)
    func processReferralSignup(
        referralCode: String,
        newUserID: String,
        platform: String = "ios",
        sourceType: ReferralSourceType = .manual,
        deviceInfo: [String: String] = [:]
    ) async throws -> ReferralProcessingResult {
        
        print("🔥 REFERRAL: Processing signup with code \(referralCode) for user \(newUserID)")
        
        // Validate referral code format
        guard FirebaseSchema.ValidationRules.validateReferralCode(referralCode) else {
            return ReferralProcessingResult(
                success: false, referralID: nil, cloutAwarded: 0,
                hypeBonus: 0.0, rewardsMaxed: false,
                message: "Invalid referral code format",
                error: "INVALID_CODE_FORMAT", referrerID: nil
            )
        }
        
        // Find referrer by referral code
        let referrerQuery = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.referralCode, isEqualTo: referralCode)
            .limit(to: 1)
            .getDocuments()
        
        guard let referrerDoc = referrerQuery.documents.first else {
            return ReferralProcessingResult(
                success: false, referralID: nil, cloutAwarded: 0,
                hypeBonus: 0.0, rewardsMaxed: false,
                message: "Referral code not found",
                error: "CODE_NOT_FOUND", referrerID: nil
            )
        }
        
        let referrerID = referrerDoc.documentID
        
        // Prevent self-referral
        guard referrerID != newUserID else {
            return ReferralProcessingResult(
                success: false, referralID: nil, cloutAwarded: 0,
                hypeBonus: 0.0, rewardsMaxed: false,
                message: "Cannot refer yourself",
                error: "SELF_REFERRAL", referrerID: nil
            )
        }
        
        // Check if user was already referred
        let existingUserDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(newUserID)
            .getDocument()
        
        if let invitedBy = existingUserDoc.data()?[FirebaseSchema.UserDocument.invitedBy] as? String,
           !invitedBy.isEmpty {
            return ReferralProcessingResult(
                success: false, referralID: nil, cloutAwarded: 0,
                hypeBonus: 0.0, rewardsMaxed: false,
                message: "User already referred by someone else",
                error: "ALREADY_REFERRED", referrerID: nil
            )
        }
        
        // Get referrer's current stats
        let referrerData = referrerDoc.data() ?? [:]
        let currentReferralCount = referrerData[FirebaseSchema.UserDocument.referralCount] as? Int ?? 0
        let currentCloutEarned = referrerData[FirebaseSchema.UserDocument.referralCloutEarned] as? Int ?? 0
        let currentClout = referrerData[FirebaseSchema.UserDocument.clout] as? Int ?? 0
        
        // Check if referrer has hit clout cap
        let rewardsMaxed = currentCloutEarned >= maxCloutFromReferrals
        let cloutToAward = rewardsMaxed ? 0 : cloutPerReferral
        let newCloutEarned = currentCloutEarned + cloutToAward
        let newHypeBonus = Double(currentReferralCount + 1) * hypeRatingBonusPerReferral
        
        // Create referral tracking document
        let referralID = FirebaseSchema.DocumentIDPatterns.generateReferralID(referrerID: referrerID)
        let referralData: [String: Any] = [
            FirebaseSchema.ReferralDocument.id: referralID,
            FirebaseSchema.ReferralDocument.referrerID: referrerID,
            FirebaseSchema.ReferralDocument.refereeID: newUserID,
            FirebaseSchema.ReferralDocument.referralCode: referralCode,
            FirebaseSchema.ReferralDocument.status: ReferralStatus.completed.rawValue,
            FirebaseSchema.ReferralDocument.createdAt: Timestamp(),
            FirebaseSchema.ReferralDocument.completedAt: Timestamp(),
            FirebaseSchema.ReferralDocument.cloutAwarded: cloutToAward,
            FirebaseSchema.ReferralDocument.hypeBonus: hypeRatingBonusPerReferral,
            FirebaseSchema.ReferralDocument.rewardsCapped: rewardsMaxed,
            FirebaseSchema.ReferralDocument.sourceType: sourceType.rawValue,
            FirebaseSchema.ReferralDocument.platform: platform,
            FirebaseSchema.ReferralDocument.ipAddress: deviceInfo["ipAddress"] ?? "",
            FirebaseSchema.ReferralDocument.deviceFingerprint: deviceInfo["deviceFingerprint"] ?? "",
            FirebaseSchema.ReferralDocument.userAgent: deviceInfo["userAgent"] ?? ""
        ]
        
        // BATCHING: Single transaction for ALL writes — referral + stats + auto-follow
        // 5 writes in 1 round trip instead of 5 separate calls
        do {
            let _ = try await db.runTransaction { transaction, errorPointer in
                
                // Write 1: Update referrer's stats
                let referrerRef = self.db.collection(FirebaseSchema.Collections.users).document(referrerID)
                transaction.updateData([
                    FirebaseSchema.UserDocument.referralCount: currentReferralCount + 1,
                    FirebaseSchema.UserDocument.referralCloutEarned: newCloutEarned,
                    FirebaseSchema.UserDocument.clout: currentClout + cloutToAward,
                    FirebaseSchema.UserDocument.hypeRatingBonus: newHypeBonus,
                    FirebaseSchema.UserDocument.referralRewardsMaxed: newCloutEarned >= self.maxCloutFromReferrals,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp(),
                    // Increment follower count for referrer
                    FirebaseSchema.UserDocument.followerCount: FieldValue.increment(Int64(1))
                ], forDocument: referrerRef)
                
                // Write 2: Update new user with referrer info
                let newUserRef = self.db.collection(FirebaseSchema.Collections.users).document(newUserID)
                transaction.updateData([
                    FirebaseSchema.UserDocument.invitedBy: referrerID,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp(),
                    // Increment following count for new user
                    FirebaseSchema.UserDocument.followingCount: FieldValue.increment(Int64(1))
                ], forDocument: newUserRef)
                
                // Write 3: Create referral tracking document
                let referralRef = self.db.collection(FirebaseSchema.Collections.referrals).document(referralID)
                transaction.setData(referralData, forDocument: referralRef)
                
                // Write 4: Auto-follow — new user follows referrer
                let followingRef = self.db.collection(FirebaseSchema.Collections.users)
                    .document(newUserID)
                    .collection("following")
                    .document(referrerID)
                transaction.setData([
                    "followeeID": referrerID,
                    "followerID": newUserID,
                    "isActive": true,
                    "createdAt": Timestamp(),
                    "source": "referral"
                ], forDocument: followingRef)
                
                // Write 5: Auto-follow — referrer gets new follower
                let followerRef = self.db.collection(FirebaseSchema.Collections.users)
                    .document(referrerID)
                    .collection("followers")
                    .document(newUserID)
                transaction.setData([
                    "followerID": newUserID,
                    "followeeID": referrerID,
                    "isActive": true,
                    "createdAt": Timestamp(),
                    "source": "referral"
                ], forDocument: followerRef)
                
                return "success"
            }
            
            print("✅ REFERRAL: Processed + auto-followed referrer \(referrerID)")
            
            // Fire-and-forget: Send follow notification to referrer via Cloud Function
            // Outside transaction so it doesn't block or risk failing the referral write
            Task {
                do {
                    let functions = Functions.functions(region: "us-central1")
                    let _ = try await functions.httpsCallable("stitchnoti_sendFollow").call([
                        "recipientID": referrerID
                    ])
                    print("🔔 REFERRAL: Follow notification sent to referrer \(referrerID)")
                } catch {
                    // Non-blocking — referral still succeeded even if notification fails
                    print("⚠️ REFERRAL: Follow notification failed (non-blocking): \(error)")
                }
            }
            
            return ReferralProcessingResult(
                success: true,
                referralID: referralID,
                cloutAwarded: cloutToAward,
                hypeBonus: newHypeBonus,
                rewardsMaxed: newCloutEarned >= maxCloutFromReferrals,
                message: rewardsMaxed ?
                    "Referral processed! (Clout reward cap reached)" :
                    "Referral successful! +\(cloutToAward) clout",
                error: nil,
                referrerID: referrerID
            )
            
        } catch {
            return ReferralProcessingResult(
                success: false, referralID: nil, cloutAwarded: 0,
                hypeBonus: 0.0, rewardsMaxed: false,
                message: "Transaction failed",
                error: error.localizedDescription, referrerID: nil
            )
        }
    }
    
    // MARK: - Organic Signup Tracking
    
    /// Track signups with no referral code for complete timeline
    /// Single write — no batching needed
    func processOrganicSignup(newUserID: String, platform: String = "ios") async {
        let organicData: [String: Any] = [
            "id": "organic_\(newUserID)_\(Int(Date().timeIntervalSince1970))",
            FirebaseSchema.ReferralDocument.referrerID: NSNull(),
            FirebaseSchema.ReferralDocument.refereeID: newUserID,
            FirebaseSchema.ReferralDocument.referralCode: NSNull(),
            FirebaseSchema.ReferralDocument.status: ReferralStatus.completed.rawValue,
            FirebaseSchema.ReferralDocument.createdAt: Timestamp(),
            FirebaseSchema.ReferralDocument.completedAt: Timestamp(),
            FirebaseSchema.ReferralDocument.cloutAwarded: 0,
            FirebaseSchema.ReferralDocument.sourceType: ReferralSourceType.organic.rawValue,
            FirebaseSchema.ReferralDocument.platform: platform
        ]
        
        do {
            try await db.collection(FirebaseSchema.Collections.referrals)
                .document("organic_\(newUserID)")
                .setData(organicData)
            print("📊 REFERRAL: Organic signup tracked for \(newUserID)")
        } catch {
            // Non-blocking — don't fail signup over tracking
            print("⚠️ REFERRAL: Failed to track organic signup: \(error)")
        }
    }
    
    // MARK: - Stats & Analytics
    
    /// Get user's referral statistics
    func getUserReferralStats(userID: String) async throws -> ReferralStats {
        print("📊 REFERRAL: Loading stats for user \(userID)")
        
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        guard userDoc.exists, let userData = userDoc.data() else {
            throw NSError(domain: "ReferralService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let referralCode = userData[FirebaseSchema.UserDocument.referralCode] as? String ?? ""
        let referralCount = userData[FirebaseSchema.UserDocument.referralCount] as? Int ?? 0
        let cloutEarned = userData[FirebaseSchema.UserDocument.referralCloutEarned] as? Int ?? 0
        let hypeBonus = userData[FirebaseSchema.UserDocument.hypeRatingBonus] as? Double ?? 0.0
        let rewardsMaxed = userData[FirebaseSchema.UserDocument.referralRewardsMaxed] as? Bool ?? false
        
        // Load recent referrals
        let referralQuery = try await db.collection(FirebaseSchema.Collections.referrals)
            .whereField(FirebaseSchema.ReferralDocument.referrerID, isEqualTo: userID)
            .order(by: FirebaseSchema.ReferralDocument.createdAt, descending: true)
            .limit(to: 10)
            .getDocuments()
        
        var recentReferrals: [ReferralInfo] = []
        var pendingCount = 0
        var monthlyCount = 0
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        for doc in referralQuery.documents {
            let data = doc.data()
            let status = ReferralStatus(rawValue: data[FirebaseSchema.ReferralDocument.status] as? String ?? "") ?? .pending
            let createdAt = (data[FirebaseSchema.ReferralDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
            
            if status == .pending { pendingCount += 1 }
            if createdAt > thirtyDaysAgo { monthlyCount += 1 }
            
            recentReferrals.append(ReferralInfo(
                id: doc.documentID,
                refereeID: data[FirebaseSchema.ReferralDocument.refereeID] as? String,
                refereeUsername: nil,
                status: status,
                createdAt: createdAt,
                completedAt: (data[FirebaseSchema.ReferralDocument.completedAt] as? Timestamp)?.dateValue(),
                cloutAwarded: data[FirebaseSchema.ReferralDocument.cloutAwarded] as? Int ?? 0,
                platform: data[FirebaseSchema.ReferralDocument.platform] as? String ?? "unknown",
                sourceType: ReferralSourceType(rawValue: data[FirebaseSchema.ReferralDocument.sourceType] as? String ?? "") ?? .manual
            ))
        }
        
        let universalLink = referralCode.isEmpty ? "" : "\(baseURL)/invite/\(referralCode)"
        
        return ReferralStats(
            totalReferrals: referralCount,
            completedReferrals: referralCount - pendingCount,
            pendingReferrals: pendingCount,
            cloutEarned: cloutEarned,
            hypeRatingBonus: hypeBonus,
            rewardsMaxed: rewardsMaxed,
            referralCode: referralCode,
            referralLink: universalLink,
            monthlyReferrals: monthlyCount,
            recentReferrals: recentReferrals
        )
    }
    
    /// Calculate hype rating bonus for user
    func calculateHypeRatingBonus(userID: String) async throws -> Double {
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        return userDoc.data()?[FirebaseSchema.UserDocument.hypeRatingBonus] as? Double ?? 0.0
    }
    
    /// Validate referral code exists and is active
    func validateReferralCode(_ code: String) async throws -> Bool {
        // Format validation
        guard FirebaseSchema.ValidationRules.validateReferralCode(code) else {
            return false
        }
        
        // Database validation — single read
        let query = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.referralCode, isEqualTo: code)
            .limit(to: 1)
            .getDocuments()
        
        return !query.documents.isEmpty
    }
    
    /// Clean up expired referral codes (admin function)
    func cleanupExpiredReferrals() async throws -> Int {
        let thirtyDaysAgo = Timestamp(date: Date().addingTimeInterval(-TimeInterval(referralExpirationDays * 24 * 60 * 60)))
        
        let expiredQuery = try await db.collection(FirebaseSchema.Collections.referrals)
            .whereField(FirebaseSchema.ReferralDocument.status, isEqualTo: ReferralStatus.pending.rawValue)
            .whereField(FirebaseSchema.ReferralDocument.createdAt, isLessThan: thirtyDaysAgo)
            .getDocuments()
        
        let batch = db.batch()
        var cleanupCount = 0
        
        for doc in expiredQuery.documents {
            batch.updateData([
                FirebaseSchema.ReferralDocument.status: ReferralStatus.expired.rawValue
            ], forDocument: doc.reference)
            cleanupCount += 1
        }
        
        if cleanupCount > 0 {
            try await batch.commit()
            print("🧹 REFERRAL: Cleaned up \(cleanupCount) expired referrals")
        }
        
        return cleanupCount
    }
    
    // MARK: - Private Helper Methods
    
    /// Generate unique referral code
    private func generateUniqueReferralCode() async throws -> String {
        var attempts = 0
        let maxAttempts = 10
        
        while attempts < maxAttempts {
            let code = FirebaseSchema.DocumentIDPatterns.generateReferralCode()
            
            // Check if code already exists — single read
            let existingQuery = try await db.collection(FirebaseSchema.Collections.users)
                .whereField(FirebaseSchema.UserDocument.referralCode, isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            
            if existingQuery.documents.isEmpty {
                return code
            }
            
            attempts += 1
        }
        
        throw NSError(domain: "ReferralService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to generate unique referral code"])
    }
    
    /// Generate shareable text for referral links
    private func generateShareText(referralCode: String) -> String {
        return """
        🎬 Welcome to Stitch Social! 🎬
        
        Hey! Thanks for signing up — stick with us, it can get a little tricky the first time!
        
        🍎 iPhone Users:
        1. Download the TestFlight app first (it's how you test our app before launch): https://apps.apple.com/app/testflight/id899247664
        2. Once TestFlight is installed, come back here and tap this link to get Stitch Social: https://testflight.apple.com/join/cXbWreGc
        3. Hit "Accept" then "Install" inside TestFlight
        4. Open Stitch Social from your home screen and create your account
        
        🤖 Android Users:
        Use this link to install directly: https://play.google.com/store/apps/details?id=com.stitchsocial.club
        
        🎁 At signup, enter this invite code to support the person who invited you: \(referralCode)
        
        Happy Stitching! 🚀✨
        """
    }
    
    // MARK: - Analytics and Monitoring
    
    /// Get referral analytics for admin dashboard
    func getReferralAnalytics(timeframe: TimeInterval = 30 * 24 * 60 * 60) async throws -> [String: Any] {
        let startDate = Timestamp(date: Date().addingTimeInterval(-timeframe))
        
        let recentReferrals = try await db.collection(FirebaseSchema.Collections.referrals)
            .whereField(FirebaseSchema.ReferralDocument.createdAt, isGreaterThan: startDate)
            .getDocuments()
        
        var totalReferrals = 0
        var completedReferrals = 0
        var organicSignups = 0
        var cloutAwarded = 0
        var platformBreakdown: [String: Int] = [:]
        var sourceBreakdown: [String: Int] = [:]
        
        for doc in recentReferrals.documents {
            let data = doc.data()
            totalReferrals += 1
            
            let sourceType = data[FirebaseSchema.ReferralDocument.sourceType] as? String ?? ""
            
            if sourceType == ReferralSourceType.organic.rawValue {
                organicSignups += 1
            }
            
            if let status = data[FirebaseSchema.ReferralDocument.status] as? String,
               status == ReferralStatus.completed.rawValue {
                completedReferrals += 1
                cloutAwarded += data[FirebaseSchema.ReferralDocument.cloutAwarded] as? Int ?? 0
            }
            
            if let platform = data[FirebaseSchema.ReferralDocument.platform] as? String {
                platformBreakdown[platform, default: 0] += 1
            }
            
            sourceBreakdown[sourceType, default: 0] += 1
        }
        
        let referredSignups = totalReferrals - organicSignups
        let conversionRate = totalReferrals > 0 ? Double(completedReferrals) / Double(totalReferrals) : 0.0
        
        return [
            "totalReferrals": totalReferrals,
            "completedReferrals": completedReferrals,
            "organicSignups": organicSignups,
            "referredSignups": referredSignups,
            "conversionRate": conversionRate,
            "totalCloutAwarded": cloutAwarded,
            "platformBreakdown": platformBreakdown,
            "sourceBreakdown": sourceBreakdown,
            "timeframeDays": Int(timeframe / (24 * 60 * 60))
        ]
    }
    
    // MARK: - Error Handling
    
    /// Map Firebase errors to user-friendly messages
    private func mapFirebaseError(_ error: Error) -> String {
        if let firebaseError = error as NSError? {
            switch firebaseError.code {
            case FirestoreErrorCode.notFound.rawValue:
                return "Referral code not found"
            case FirestoreErrorCode.permissionDenied.rawValue:
                return "Permission denied"
            case FirestoreErrorCode.unavailable.rawValue:
                return "Network error - please try again"
            default:
                return "An error occurred: \(firebaseError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}
