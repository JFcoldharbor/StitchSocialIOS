//
//  ReferralService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Complete Referral System Implementation
//  Dependencies: FirebaseSchema (Layer 3), UserTier (Layer 1)
//  Features: Code generation, link sharing, reward tracking, fraud prevention
//

import Foundation
import Firebase
import FirebaseFirestore

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
}

/// User referral statistics
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
        print("🔗 REFERRAL: Generating referral link for user \(userID)")
        
        // Check if user already has a referral code
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        var referralCode: String
        
        if let existingCode = userDoc.data()?[FirebaseSchema.UserDocument.referralCode] as? String,
           !existingCode.isEmpty {
            referralCode = existingCode
            print("✅ REFERRAL: Using existing code \(referralCode)")
        } else {
            // Generate new unique referral code
            referralCode = try await generateUniqueReferralCode()
            
            // Save referral code to user document
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .updateData([
                    FirebaseSchema.UserDocument.referralCode: referralCode,
                    FirebaseSchema.UserDocument.referralCreatedAt: Timestamp(),
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ])
            
            print("✅ REFERRAL: Generated new code \(referralCode)")
        }
        
        let expiresAt = Date().addingTimeInterval(TimeInterval(referralExpirationDays * 24 * 60 * 60))
        
        return ReferralLink(
            code: referralCode,
            universalLink: "\(baseURL)/invite/\(referralCode)",
            deepLink: "\(deepLinkScheme)://invite/\(referralCode)",
            shareText: generateShareText(referralCode: referralCode),
            expiresAt: expiresAt
        )
    }
    
    /// Process referral code during user signup
    func processReferralSignup(
        referralCode: String,
        newUserID: String,
        platform: String = "ios",
        sourceType: ReferralSourceType = .link,
        deviceInfo: [String: String] = [:]
    ) async throws -> ReferralProcessingResult {
        
        print("🔥 REFERRAL: Processing signup with code \(referralCode) for user \(newUserID)")
        
        // Validate referral code format
        guard FirebaseSchema.ValidationRules.validateReferralCode(referralCode) else {
            return ReferralProcessingResult(
                success: false,
                referralID: nil,
                cloutAwarded: 0,
                hypeBonus: 0.0,
                rewardsMaxed: false,
                message: "Invalid referral code format",
                error: "INVALID_CODE_FORMAT"
            )
        }
        
        // Find referrer by referral code
        let referrerQuery = try await db.collection(FirebaseSchema.Collections.users)
            .whereField(FirebaseSchema.UserDocument.referralCode, isEqualTo: referralCode)
            .limit(to: 1)
            .getDocuments()
        
        guard let referrerDoc = referrerQuery.documents.first else {
            return ReferralProcessingResult(
                success: false,
                referralID: nil,
                cloutAwarded: 0,
                hypeBonus: 0.0,
                rewardsMaxed: false,
                message: "Referral code not found",
                error: "CODE_NOT_FOUND"
            )
        }
        
        let referrerID = referrerDoc.documentID
        
        // Prevent self-referral
        guard referrerID != newUserID else {
            return ReferralProcessingResult(
                success: false,
                referralID: nil,
                cloutAwarded: 0,
                hypeBonus: 0.0,
                rewardsMaxed: false,
                message: "Cannot refer yourself",
                error: "SELF_REFERRAL"
            )
        }
        
        // Check if user was already referred
        let existingUserDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(newUserID)
            .getDocument()
        
        if let invitedBy = existingUserDoc.data()?[FirebaseSchema.UserDocument.invitedBy] as? String,
           !invitedBy.isEmpty {
            return ReferralProcessingResult(
                success: false,
                referralID: nil,
                cloutAwarded: 0,
                hypeBonus: 0.0,
                rewardsMaxed: false,
                message: "User already referred by someone else",
                error: "ALREADY_REFERRED"
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
        
        // Use transaction to ensure consistency
        do {
            let result = try await db.runTransaction { transaction, errorPointer in
                
                // Update referrer's stats
                let referrerRef = self.db.collection(FirebaseSchema.Collections.users).document(referrerID)
                transaction.updateData([
                    FirebaseSchema.UserDocument.referralCount: currentReferralCount + 1,
                    FirebaseSchema.UserDocument.referralCloutEarned: newCloutEarned,
                    FirebaseSchema.UserDocument.clout: currentClout + cloutToAward,
                    FirebaseSchema.UserDocument.hypeRatingBonus: newHypeBonus,
                    FirebaseSchema.UserDocument.referralRewardsMaxed: newCloutEarned >= self.maxCloutFromReferrals,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ], forDocument: referrerRef)
                
                // Update new user with referrer info
                let newUserRef = self.db.collection(FirebaseSchema.Collections.users).document(newUserID)
                transaction.updateData([
                    FirebaseSchema.UserDocument.invitedBy: referrerID,
                    FirebaseSchema.UserDocument.updatedAt: Timestamp()
                ], forDocument: newUserRef)
                
                // Create referral tracking document
                let referralRef = self.db.collection(FirebaseSchema.Collections.referrals).document(referralID)
                transaction.setData(referralData, forDocument: referralRef)
                
                return "success"
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
                error: nil
            )
            
        } catch {
            return ReferralProcessingResult(
                success: false,
                referralID: nil,
                cloutAwarded: 0,
                hypeBonus: 0.0,
                rewardsMaxed: false,
                message: "Transaction failed",
                error: error.localizedDescription
            )
        }
    }
    
    /// Get user's referral statistics
    func getUserReferralStats(userID: String) async throws -> ReferralStats {
        print("📊 REFERRAL: Loading stats for user \(userID)")
        
        // Get user document
        let userDoc = try await db.collection(FirebaseSchema.Collections.users)
            .document(userID)
            .getDocument()
        
        guard let userData = userDoc.data() else {
            throw NSError(domain: "ReferralService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        // Extract referral data from user document
        let referralCode = userData[FirebaseSchema.UserDocument.referralCode] as? String ?? ""
        let totalReferrals = userData[FirebaseSchema.UserDocument.referralCount] as? Int ?? 0
        let cloutEarned = userData[FirebaseSchema.UserDocument.referralCloutEarned] as? Int ?? 0
        let hypeBonus = userData[FirebaseSchema.UserDocument.hypeRatingBonus] as? Double ?? 0.0
        let rewardsMaxed = userData[FirebaseSchema.UserDocument.referralRewardsMaxed] as? Bool ?? false
        
        // Get detailed referral history
        let referralsQuery = try await db.collection(FirebaseSchema.Collections.referrals)
            .whereField(FirebaseSchema.ReferralDocument.referrerID, isEqualTo: userID)
            .order(by: FirebaseSchema.ReferralDocument.createdAt, descending: true)
            .limit(to: 20)
            .getDocuments()
        
        var completedReferrals = 0
        var pendingReferrals = 0
        var monthlyReferrals = 0
        var recentReferrals: [ReferralInfo] = []
        
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        for doc in referralsQuery.documents {
            let data = doc.data()
            let status = ReferralStatus(rawValue: data[FirebaseSchema.ReferralDocument.status] as? String ?? "") ?? .failed
            let createdAt = (data[FirebaseSchema.ReferralDocument.createdAt] as? Timestamp)?.dateValue() ?? Date()
            
            switch status {
            case .completed:
                completedReferrals += 1
            case .pending:
                pendingReferrals += 1
            default:
                break
            }
            
            if createdAt > thirtyDaysAgo {
                monthlyReferrals += 1
            }
            
            let referralInfo = ReferralInfo(
                id: doc.documentID,
                refereeID: data[FirebaseSchema.ReferralDocument.refereeID] as? String,
                refereeUsername: nil, // Would need additional lookup
                status: status,
                createdAt: createdAt,
                completedAt: (data[FirebaseSchema.ReferralDocument.completedAt] as? Timestamp)?.dateValue(),
                cloutAwarded: data[FirebaseSchema.ReferralDocument.cloutAwarded] as? Int ?? 0,
                platform: data[FirebaseSchema.ReferralDocument.platform] as? String ?? "unknown",
                sourceType: ReferralSourceType(rawValue: data[FirebaseSchema.ReferralDocument.sourceType] as? String ?? "") ?? .link
            )
            
            recentReferrals.append(referralInfo)
        }
        
        let referralLink = referralCode.isEmpty ? "" : "\(baseURL)/invite/\(referralCode)"
        
        return ReferralStats(
            totalReferrals: totalReferrals,
            completedReferrals: completedReferrals,
            pendingReferrals: pendingReferrals,
            cloutEarned: cloutEarned,
            hypeRatingBonus: hypeBonus,
            rewardsMaxed: rewardsMaxed,
            referralCode: referralCode,
            referralLink: referralLink,
            monthlyReferrals: monthlyReferrals,
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
        
        // Database validation
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
            
            // Check if code already exists
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
        Join me on Stitch Social! 🎬✨
        
        Create awesome videos and join the conversation. Get bonus clout when you sign up with my code: \(referralCode)
        
        \(baseURL)/invite/\(referralCode)
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
        var cloutAwarded = 0
        var platformBreakdown: [String: Int] = [:]
        var sourceBreakdown: [String: Int] = [:]
        
        for doc in recentReferrals.documents {
            let data = doc.data()
            totalReferrals += 1
            
            if let status = data[FirebaseSchema.ReferralDocument.status] as? String,
               status == ReferralStatus.completed.rawValue {
                completedReferrals += 1
                cloutAwarded += data[FirebaseSchema.ReferralDocument.cloutAwarded] as? Int ?? 0
            }
            
            if let platform = data[FirebaseSchema.ReferralDocument.platform] as? String {
                platformBreakdown[platform, default: 0] += 1
            }
            
            if let source = data[FirebaseSchema.ReferralDocument.sourceType] as? String {
                sourceBreakdown[source, default: 0] += 1
            }
        }
        
        let conversionRate = totalReferrals > 0 ? Double(completedReferrals) / Double(totalReferrals) : 0.0
        
        return [
            "totalReferrals": totalReferrals,
            "completedReferrals": completedReferrals,
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
