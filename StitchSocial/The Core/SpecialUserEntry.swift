//
//  SpecialUsersConfig.swift
//  CleanBeta
//
//  Foundation layer - References existing UserTier and BadgeType
//  Centralized configuration for all special users (founders, celebrities, ambassadors)
//  Separated for easy maintenance and future expansion - REFERENCES existing types
//

import Foundation

// MARK: - Special User Configuration Structure

/// Configuration for special users with custom privileges and starting benefits
/// Uses existing UserTier and BadgeType from your current system
struct SpecialUserEntry: Codable, Hashable {
    let email: String
    let role: SpecialUserRole
    let tierRawValue: String // References existing UserTier.rawValue
    let startingClout: Int
    let customTitle: String
    let customBio: String
    let badgeRawValues: [String] // References existing BadgeType.rawValue
    let specialPerks: [String]
    let isAutoFollowed: Bool
    let priority: Int // Higher number = higher priority
    
    // Computed properties for easy access
    var displayRole: String {
        role.displayName
    }
    
    var isFounder: Bool {
        role == .founder || role == .coFounder
    }
    
    var isCelebrity: Bool {
        role == .celebrity || role == .ambassador
    }
}

/// Special user role categories
enum SpecialUserRole: String, CaseIterable, Codable {
    case founder = "founder"
    case coFounder = "co_founder" 
    case employee = "employee"
    case celebrity = "celebrity"
    case ambassador = "ambassador"
    case affiliate = "affiliate"
    case influencer = "special_influencer"
    case partner = "special_partner"
    
    var displayName: String {
        switch self {
        case .founder: return "Founder"
        case .coFounder: return "Co-Founder"
        case .employee: return "Employee"
        case .celebrity: return "Celebrity"
        case .ambassador: return "Ambassador"
        case .affiliate: return "Affiliate"
        case .influencer: return "Special Influencer"
        case .partner: return "Special Partner"
        }
    }
    
    var defaultPriority: Int {
        switch self {
        case .founder: return 1000
        case .coFounder: return 900
        case .employee: return 800
        case .celebrity: return 700
        case .ambassador: return 600
        case .influencer: return 500
        case .partner: return 400
        case .affiliate: return 300
        }
    }
}

// MARK: - Special Users Registry

/// Centralized registry of all special users - REFERENCES existing UserTier/BadgeType
/// This is the master list that other systems can reference
struct SpecialUsersConfig {
    
    // MARK: - Special Users Database
    
    /// Complete list of all special users - Easy to modify and expand
    /// Uses raw values to reference existing UserTier and BadgeType enums
    static let specialUsersList: [String: SpecialUserEntry] = [
        
        // MARK: - FOUNDERS (Highest Priority)
        
        "james@stitchsocial.me": SpecialUserEntry(
            email: "james@stitchsocial.me",
            role: .founder,
            tierRawValue: "founder", // References UserTier.founder.rawValue
            startingClout: 50000,
            customTitle: "Founder & CEO 👑",
            customBio: "Founder of Stitch Social 🎬 | Building the future of social video",
            badgeRawValues: ["founder_crown", "verified", "early_adopter"], // References BadgeType raw values
            specialPerks: ["auto_follow", "priority_support", "clout_per_new_user", "admin_access"],
            isAutoFollowed: true,
            priority: 1000
        ),
        
        "justin@stitchsocial.me": SpecialUserEntry(
            email: "justin@stitchsocial.me",
            role: .founder,
            tierRawValue: "founder",
            startingClout: 35000,
            customTitle: "Co-Founder 👑",
            customBio: "Co-Founder of Stitch Social 🎬 | Creating authentic connections",
            badgeRawValues: ["founder_crown", "verified", "early_adopter"],
            specialPerks: ["priority_support", "admin_access"],
            isAutoFollowed: false,
            priority: 1000
        ),
        
        // MARK: - CO-FOUNDERS
        
        "bernadette@stitchsocial.me": SpecialUserEntry(
            email: "bernadette@stitchsocial.me",
            role: .coFounder,
            tierRawValue: "co_founder", // References UserTier.coFounder.rawValue
            startingClout: 25000,
            customTitle: "Co-Founder 💎",
            customBio: "Co-Founder of Stitch Social 🎬 | Building community",
            badgeRawValues: ["cofounder_crown", "verified", "early_adopter"],
            specialPerks: ["priority_support", "exclusive_features", "leadership_access"],
            isAutoFollowed: false,
            priority: 900
        ),
        
        "sandra@stitchsocial.me": SpecialUserEntry(
            email: "sandra@stitchsocial.me",
            role: .coFounder,
            tierRawValue: "co_founder",
            startingClout: 25000,
            customTitle: "Co-Founder 💎",
            customBio: "Co-Founder of Stitch Social 🎬 | Creative visionary",
            badgeRawValues: ["cofounder_crown", "verified", "early_adopter"],
            specialPerks: ["priority_support", "exclusive_features", "leadership_access"],
            isAutoFollowed: false,
            priority: 900
        ),
        
        // MARK: - CELEBRITY AMBASSADORS
        
        "teddyruks@gmail.com": SpecialUserEntry(
            email: "teddyruks@gmail.com",
            role: .celebrity,
            tierRawValue: "top_creator", // References UserTier.topCreator.rawValue
            startingClout: 20000,
            customTitle: "Celebrity Ambassador ⭐",
            customBio: "Reality TV Star | Black Ink Crew 🖋️ | Ambassador for Stitch Social",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "verified_badge"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        "chaneyvisionent@gmail.com": SpecialUserEntry(
            email: "chaneyvisionent@gmail.com",
            role: .celebrity,
            tierRawValue: "top_creator",
            startingClout: 20000,
            customTitle: "TV Legend Ambassador 📺",
            customBio: "Poot from The Wire 🎭 | Actor & Producer | Chaney Vision Entertainment",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "verified_badge"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        // MARK: - MUSIC INDUSTRY
        
        "afterflaspoint@icloud.com": SpecialUserEntry(
            email: "afterflaspoint@icloud.com",
            role: .celebrity,
            tierRawValue: "top_creator",
            startingClout: 25000,
            customTitle: "Diamond Selling Artist, Streamer 🎵",
            customBio: "1/2 of the dynamic group Rae Sremmurd 👑 | Music Industry Veteran",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "music_industry_perks"],
            isAutoFollowed: false,
            priority: 750
        ),
        
        // MARK: - TECH AFFILIATES
        
        "floydjrsullivan@yahoo.com": SpecialUserEntry(
            email: "floydjrsullivan@yahoo.com",
            role: .affiliate,
            tierRawValue: "influencer", // References UserTier.influencer.rawValue
            startingClout: 12000,
            customTitle: "Veteran, Boss, Gamer 🎵",
            customBio: "Brother of Rae Sremmurd 👑 | King of my own Destiny | Family First",
            badgeRawValues: ["verified", "early_adopter"],
            specialPerks: ["affiliate_support", "exclusive_features", "family_connection"],
            isAutoFollowed: false,
            priority: 350
        ),
        
        "srbentleyga@gmail.com": SpecialUserEntry(
            email: "srbentleyga@gmail.com",
            role: .affiliate,
            tierRawValue: "influencer",
            startingClout: 5000,
            customTitle: "Tech Developer 💻",
            customBio: "Technology Developer | Early Adopter | Building the future",
            badgeRawValues: ["verified", "early_adopter"],
            specialPerks: ["affiliate_support", "developer_tools", "early_access"],
            isAutoFollowed: false,
            priority: 350
        )
    ]
    
    // MARK: - Helper Methods - REFERENCE BRIDGE to existing UserTier system
    
    /// Get special configuration for user by email
    static func getSpecialUser(for email: String) -> SpecialUserEntry? {
        return specialUsersList[email.lowercased()]
    }
    
    /// Check if user is special
    static func isSpecialUser(_ email: String) -> Bool {
        return specialUsersList[email.lowercased()] != nil
    }
    
    /// Get all special users by role
    static func getUsers(by role: SpecialUserRole) -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.role == role }
    }
    
    /// Get all founders (founder + co-founder)
    static func getAllFounders() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.isFounder }
    }
    
    /// Get all celebrities (celebrity + ambassador)
    static func getAllCelebrities() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.isCelebrity }
    }
    
    /// Get auto-follow users (users that new users should automatically follow)
    static func getAutoFollowUsers() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.isAutoFollowed }
    }
    
    /// Get users sorted by priority (highest first)
    static func getUsersByPriority() -> [SpecialUserEntry] {
        return specialUsersList.values.sorted { $0.priority > $1.priority }
    }
    
    /// Get starting clout for user (with fallback)
    static func getStartingClout(for email: String) -> Int {
        return getSpecialUser(for: email)?.startingClout ?? 1500 // Default starting clout
    }
    
    /// Get initial badges for user (returns raw values to be converted by existing system)
    static func getInitialBadgeRawValues(for email: String) -> [String] {
        if let user = getSpecialUser(for: email) {
            return user.badgeRawValues
        } else {
            return ["early_adopter"] // Default badge for beta users
        }
    }
    
    /// Get special perks for user
    static func getSpecialPerks(for email: String) -> [String] {
        return getSpecialUser(for: email)?.specialPerks ?? []
    }
    
    /// Get custom title for user
    static func getCustomTitle(for email: String) -> String? {
        return getSpecialUser(for: email)?.customTitle
    }
    
    /// Get custom bio for user
    static func getCustomBio(for email: String) -> String? {
        return getSpecialUser(for: email)?.customBio
    }
    
    /// Get tier raw value for user (to be converted to UserTier by existing system)
    static func getTierRawValue(for email: String) -> String? {
        return getSpecialUser(for: email)?.tierRawValue
    }
}

// MARK: - Special User Categories

extension SpecialUsersConfig {
    
    /// Statistics about special users
    static var statistics: SpecialUserStatistics {
        let users = Array(specialUsersList.values)
        return SpecialUserStatistics(
            totalSpecialUsers: users.count,
            foundersCount: users.filter { $0.role == .founder }.count,
            coFoundersCount: users.filter { $0.role == .coFounder }.count,
            employeesCount: users.filter { $0.role == .employee }.count,
            celebritiesCount: users.filter { $0.role == .celebrity }.count,
            ambassadorsCount: users.filter { $0.role == .ambassador }.count,
            affiliatesCount: users.filter { $0.role == .affiliate }.count,
            autoFollowCount: users.filter { $0.isAutoFollowed }.count,
            totalStartingClout: users.reduce(0) { $0 + $1.startingClout }
        )
    }
}

// MARK: - Supporting Types

/// Statistics about the special users system
struct SpecialUserStatistics: Codable {
    let totalSpecialUsers: Int
    let foundersCount: Int
    let coFoundersCount: Int
    let employeesCount: Int
    let celebritiesCount: Int
    let ambassadorsCount: Int
    let affiliatesCount: Int
    let autoFollowCount: Int
    let totalStartingClout: Int
    
    var averageStartingClout: Double {
        return totalSpecialUsers > 0 ? Double(totalStartingClout) / Double(totalSpecialUsers) : 0
    }
}
// MARK: - Future Expansion Templates

/*
 
 EASY EXPANSION GUIDE:
 
 1. ADD NEW CELEBRITY:
    - Copy template above
    - Fill in email, title, bio
    - Set appropriate clout (15k-30k for celebrities)
    - Add to appropriate role category
    - Set priority (700+ for celebrities)
 
 2. ADD NEW EMPLOYEE:
    - Use employee template
    - Set clout around 15k
    - Add employee_crown badge
    - Set priority around 800
 
 3. ADD NEW AMBASSADOR:
    - Use ambassador template
    - Set clout around 10k
    - Add ambassador_crown badge
    - Set priority around 600
 
 4. MODIFY EXISTING USER:
    - Find user in list above
    - Update any field (clout, title, bio, badges, perks)
    - Save file - changes take effect immediately
 
 5. DEACTIVATE USER:
    - Comment out the user entry with /* */
    - Or remove entirely
 
 This file is designed to be easily modified without touching any other code!
 
 */
