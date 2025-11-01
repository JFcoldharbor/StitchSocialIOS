//
//  SpecialUserEntry.swift
//  StitchSocial
//
//  Foundation layer - References existing UserTier and BadgeType
//  Centralized configuration for all special users (founders, celebrities, ambassadors)
//  Updated: Added Puma, ohshitsad, Walt, email.euni with proper tier values
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
    case advisor = "advisor"
    
    var displayName: String {
        switch self {
        case .founder: return "Founder"
        case .coFounder: return "Co-Founder"
        case .employee: return "Employee"
        case .celebrity: return "Celebrity"
        case .ambassador: return "Ambassador"
        case .affiliate: return "Affiliate"
        case .influencer: return "Influencer"
        case .partner: return "Special Partner"
        case .advisor: return "Advisor"
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
        case .advisor: return 550
        }
    }
}

// MARK: - Special Users Registry

/// Centralized registry of all special users - COMPLETE LIST
/// This is the master list that other systems can reference
struct SpecialUsersConfig {
    
    // MARK: - Special Users Database - COMPLETE UPDATED LIST
    
    /// Complete list of all special users
    /// UPDATED: Added Puma, ohshitsad, Walt, email.euni
    /// FIXED: Changed tierRawValue from "celebrity" to "ambassador" for Black Ink users
    static let specialUsersList: [String: SpecialUserEntry] = [
        
        // MARK: - FOUNDER (AUTO-FOLLOW ONLY)
        
        "james@stitchsocial.me": SpecialUserEntry(
            email: "james@stitchsocial.me",
            role: .founder,
            tierRawValue: "founder",
            startingClout: 50000,
            customTitle: "Founder & CEO 👑",
            customBio: "Founder of Stitch Social 🎬 | Building the future of social video",
            badgeRawValues: ["founder_crown", "verified", "early_adopter"],
            specialPerks: ["auto_follow", "unfollow_protection", "priority_support", "admin_access", "clout_per_new_user"],
            isAutoFollowed: true,
            priority: 1000
        ),
        
        // MARK: - CO-FOUNDER (NO AUTO-FOLLOW)
        
        "bernadette@stitchsocial.me": SpecialUserEntry(
            email: "bernadette@stitchsocial.me",
            role: .coFounder,
            tierRawValue: "co_founder",
            startingClout: 25000,
            customTitle: "Co-Founder 💎",
            customBio: "Co-Founder of Stitch Social 🎬 | Building community through authentic connections",
            badgeRawValues: ["cofounder_crown", "verified", "early_adopter"],
            specialPerks: ["priority_support", "exclusive_features", "leadership_access"],
            isAutoFollowed: false,
            priority: 900
        ),
        
        // MARK: - FITNESS INFLUENCER
        
        "ironmanfitness662@yahoo.com": SpecialUserEntry(
            email: "ironmanfitness662@yahoo.com",
            role: .influencer,
            tierRawValue: "influencer",
            startingClout: 15000,
            customTitle: "Fitness Influencer 💪",
            customBio: "Iron Man Fitness | Transforming lives through fitness and wellness content",
            badgeRawValues: ["influencer_crown", "verified", "fitness"],
            specialPerks: ["verified_badge", "exclusive_features", "fitness_content"],
            isAutoFollowed: false,
            priority: 500
        ),
        
        // MARK: - SOCIAL INFLUENCERS
        
        "dpalance28@gmail.com": SpecialUserEntry(
            email: "dpalance28@gmail.com",
            role: .influencer,
            tierRawValue: "influencer",
            startingClout: 15000,
            customTitle: "Social Influencer ⭐",
            customBio: "Social Media Influencer | Creating engaging content and authentic connections",
            badgeRawValues: ["influencer_crown", "verified", "social"],
            specialPerks: ["verified_badge", "exclusive_features", "social_content"],
            isAutoFollowed: false,
            priority: 500
        ),
        
        "email.euni@gmail.com": SpecialUserEntry(
            email: "email.euni@gmail.com",
            role: .influencer,
            tierRawValue: "influencer",
            startingClout: 12500,
            customTitle: "Influencer ⭐",
            customBio: "Influencer | Connected to Teddy Ruks | Ambassador to Stitch",
            badgeRawValues: ["influencer_crown", "verified"],
            specialPerks: ["verified_badge", "exclusive_features"],
            isAutoFollowed: false,
            priority: 500
        ),
        
        "kiakallen@gmail.com": SpecialUserEntry(
            email: "kiakallen@gmail.com",
            role: .influencer,
            tierRawValue: "influencer",
            startingClout: 15000,
            customTitle: "Social Influencer ⭐",
            customBio: "Content Creator & Social Influencer | Authentic storytelling and community building",
            badgeRawValues: ["influencer_crown", "verified", "social"],
            specialPerks: ["verified_badge", "exclusive_features", "content_creation"],
            isAutoFollowed: false,
            priority: 500
        ),
        
        // MARK: - STRATEGIC ADVISOR
        
        "janpaulmedina@gmail.com": SpecialUserEntry(
            email: "janpaulmedina@gmail.com",
            role: .advisor,
            tierRawValue: "partner",
            startingClout: 15000,
            customTitle: "Strategic Advisor 🎯",
            customBio: "Strategic Advisor | Helping shape the future of social video and community engagement",
            badgeRawValues: ["advisor_crown", "verified", "strategic"],
            specialPerks: ["advisor_access", "verified_badge", "strategic_input"],
            isAutoFollowed: false,
            priority: 550
        ),
        
        // MARK: - BLACK INK AMBASSADORS
        
        "pumanyc213@gmail.com": SpecialUserEntry(
            email: "pumanyc213@gmail.com",
            role: .ambassador,
            tierRawValue: "ambassador",
            startingClout: 20000,
            customTitle: "Black Ink Ambassador 🎨",
            customBio: "Black Ink Original Cast Member | Father | Cannabis Expert | Ambassador to Stitch",
            badgeRawValues: ["ambassador_crown", "verified", "tv_star"],
            specialPerks: ["verified_badge", "exclusive_features", "priority_support"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        "ohshitsad@gmail.com": SpecialUserEntry(
            email: "ohshitsad@gmail.com",
            role: .ambassador,
            tierRawValue: "ambassador",
            startingClout: 15000,
            customTitle: "Black Ink Tattoo Artist 🎨",
            customBio: "Original Black Ink Cast | Tattoo Artist Enthusiast | Ambassador to Stitch",
            badgeRawValues: ["ambassador_crown", "verified", "tv_star"],
            specialPerks: ["verified_badge", "exclusive_features", "priority_support"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        "everythingaboutwalt@gmail.com": SpecialUserEntry(
            email: "everythingaboutwalt@gmail.com",
            role: .ambassador,
            tierRawValue: "ambassador",
            startingClout: 15000,
            customTitle: "Black Ink Ambassador 🎨",
            customBio: "Black Ink Cast Member | Ambassador to Stitch",
            badgeRawValues: ["ambassador_crown", "verified", "tv_star"],
            specialPerks: ["verified_badge", "exclusive_features", "priority_support"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        "dennis.mcdonald5@icloud.com": SpecialUserEntry(
            email: "dennis.mcdonald5@icloud.com",
            role: .ambassador,
            tierRawValue: "ambassador",
            startingClout: 12500,
            customTitle: "Actor 🎬",
            customBio: "Actor | Known for Bad Boys | Ambassador to Stitch",
            badgeRawValues: ["ambassador_crown", "verified", "film_star"],
            specialPerks: ["verified_badge", "exclusive_features", "priority_support"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        // MARK: - CELEBRITY AMBASSADORS
        
        "teddyruks@gmail.com": SpecialUserEntry(
            email: "teddyruks@gmail.com",
            role: .celebrity,
            tierRawValue: "elite",
            startingClout: 20000,
            customTitle: "Celebrity Ambassador ⭐",
            customBio: "Reality TV Star | Black Ink Crew 🖋️ | Celebrity Ambassador for Stitch Social",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "verified_badge"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        "chaneyvisionent@gmail.com": SpecialUserEntry(
            email: "chaneyvisionent@gmail.com",
            role: .celebrity,
            tierRawValue: "elite",
            startingClout: 20000,
            customTitle: "TV Legend Ambassador 📺",
            customBio: "Poot from The Wire 🎭 | Actor & Producer | Chaney Vision Entertainment",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "verified_badge"],
            isAutoFollowed: false,
            priority: 700
        ),
        
        // MARK: - MUSIC INDUSTRY / RAE SREMMURD FAMILY
        
        "afterflaspoint@icloud.com": SpecialUserEntry(
            email: "afterflaspoint@icloud.com",
            role: .celebrity,
            tierRawValue: "elite",
            startingClout: 25000,
            customTitle: "Diamond Selling Artist, Streamer 🎵",
            customBio: "1/2 of the dynamic group Rae Sremmurd 👑 | Music Industry Veteran",
            badgeRawValues: ["celebrity_crown", "verified", "early_adopter"],
            specialPerks: ["celebrity_support", "exclusive_features", "music_industry_perks"],
            isAutoFollowed: false,
            priority: 750
        ),
        
        "floydjrsullivan@yahoo.com": SpecialUserEntry(
            email: "floydjrsullivan@yahoo.com",
            role: .affiliate,
            tierRawValue: "influencer",
            startingClout: 12000,
            customTitle: "Veteran, Boss, Gamer 🎵",
            customBio: "Brother of Rae Sremmurd 👑 | King of my own Destiny | Family First",
            badgeRawValues: ["verified", "early_adopter"],
            specialPerks: ["affiliate_support", "exclusive_features", "family_connection"],
            isAutoFollowed: false,
            priority: 350
        ),
        
        // MARK: - TECH AFFILIATES
        
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
    
    // MARK: - Access Methods
    
    /// Get special user entry by email (case insensitive)
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
    
    /// Get all influencers
    static func getAllInfluencers() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.role == .influencer }
    }
    
    /// Get all advisors
    static func getAllAdvisors() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.role == .advisor }
    }
    
    /// Get all affiliates
    static func getAllAffiliates() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.role == .affiliate }
    }
    
    /// Get auto-follow users (ONLY JAMES FORTUNE)
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

// MARK: - Special User Categories & Statistics

extension SpecialUsersConfig {
    
    /// Statistics about special users (UPDATED)
    static var statistics: SpecialUserStatistics {
        let users = Array(specialUsersList.values)
        return SpecialUserStatistics(
            totalSpecialUsers: users.count,
            foundersCount: users.filter { $0.role == .founder }.count,
            coFoundersCount: users.filter { $0.role == .coFounder }.count,
            employeesCount: users.filter { $0.role == .employee }.count,
            celebritiesCount: users.filter { $0.role == .celebrity }.count,
            ambassadorsCount: users.filter { $0.role == .ambassador }.count,
            influencersCount: users.filter { $0.role == .influencer }.count,
            advisorsCount: users.filter { $0.role == .advisor }.count,
            affiliatesCount: users.filter { $0.role == .affiliate }.count,
            autoFollowCount: users.filter { $0.isAutoFollowed }.count,
            totalStartingClout: users.reduce(0) { $0 + $1.startingClout }
        )
    }
    
    /// Print current configuration summary
    static func printConfigurationSummary() {
        let stats = statistics
        print("🌟 SPECIAL USERS CONFIG SUMMARY:")
        print("   Total Special Users: \(stats.totalSpecialUsers)")
        print("   Founders: \(stats.foundersCount)")
        print("   Co-Founders: \(stats.coFoundersCount)")
        print("   Ambassadors: \(stats.ambassadorsCount)")
        print("   Influencers: \(stats.influencersCount)")
        print("   Advisors: \(stats.advisorsCount)")
        print("   Celebrities: \(stats.celebritiesCount)")
        print("   Affiliates: \(stats.affiliatesCount)")
        print("   Auto-Follow Users: \(stats.autoFollowCount)")
        print("   Total Starting Clout: \(stats.totalStartingClout)")
        print("   Average Starting Clout: \(Int(stats.averageStartingClout))")
        print("   Black Ink Cast: \(getAllUsers(containing: "black ink").count)")
    }
    
    /// Get users containing specific text in bio/title
    static func getAllUsers(containing text: String) -> [SpecialUserEntry] {
        return specialUsersList.values.filter {
            $0.customBio.lowercased().contains(text.lowercased()) ||
            $0.customTitle.lowercased().contains(text.lowercased())
        }
    }
}

// MARK: - Supporting Types

/// Statistics about the special users system (UPDATED)
struct SpecialUserStatistics: Codable {
    let totalSpecialUsers: Int
    let foundersCount: Int
    let coFoundersCount: Int
    let employeesCount: Int
    let celebritiesCount: Int
    let ambassadorsCount: Int
    let influencersCount: Int
    let advisorsCount: Int
    let affiliatesCount: Int
    let autoFollowCount: Int
    let totalStartingClout: Int
    
    var averageStartingClout: Double {
        return totalSpecialUsers > 0 ? Double(totalStartingClout) / Double(totalSpecialUsers) : 0
    }
}

// MARK: - Auto-Follow Integration

extension SpecialUsersConfig {
    
    static func detectSpecialUser(email: String) -> SpecialUserEntry? {
        return getSpecialUser(for: email)
    }
    
    /// Get James Fortune's user entry for auto-follow (ONLY AUTO-FOLLOW USER)
    static func getJamesFortune() -> SpecialUserEntry? {
        return getSpecialUser(for: "james@stitchsocial.me")
    }
    
    /// Check if user should be protected from unfollowing
    static func isProtectedFromUnfollow(_ email: String) -> Bool {
        guard let user = getSpecialUser(for: email) else { return false }
        return user.specialPerks.contains("unfollow_protection")
    }
    
    /// Get all users with unfollow protection (currently only James)
    static func getProtectedUsers() -> [SpecialUserEntry] {
        return specialUsersList.values.filter { $0.specialPerks.contains("unfollow_protection") }
    }
    
    /// Validate auto-follow configuration (should only be James)
    static func validateAutoFollowConfig() -> Bool {
        let autoFollowUsers = getAutoFollowUsers()
        let isValid = autoFollowUsers.count == 1 && autoFollowUsers.first?.email == "james@stitchsocial.me"
        
        if !isValid {
            print("⚠️ AUTO-FOLLOW CONFIG ERROR: Only James Fortune should have auto-follow enabled")
        } else {
            print("✅ AUTO-FOLLOW CONFIG: Correctly configured for James Fortune only")
        }
        
        return isValid
    }
}

// MARK: - Future Expansion Templates

/*
 
 COMPLETE SPECIAL USERS LIST (15 total):
 
 ✅ james@stitchsocial.me - Founder (AUTO-FOLLOW ONLY)
 ✅ bernadette@stitchsocial.me - Co-Founder
 ✅ ironmanfitness662@yahoo.com - Fitness Influencer (15k)
 ✅ dpalance28@gmail.com - Social Influencer (15k)
 ✅ email.euni@gmail.com - Influencer (12.5k) - NEW
 ✅ kiakallen@gmail.com - Social Influencer (15k)
 ✅ janpaulmedina@gmail.com - Strategic Advisor (15k)
 ✅ pumanyc213@gmail.com - Black Ink Ambassador (20k) - NEW
 ✅ ohshitsad@gmail.com - Black Ink Ambassador (15k) - NEW
 ✅ everythingaboutwalt@gmail.com - Black Ink Ambassador (15k) - NEW
 ✅ teddyruks@gmail.com - Celebrity Ambassador (20k)
 ✅ chaneyvisionent@gmail.com - TV Legend Ambassador (20k)
 ✅ afterflaspoint@icloud.com - Music Artist/Rae Sremmurd (25k)
 ✅ floydjrsullivan@yahoo.com - Music Family/Brother (12k)
 ✅ srbentleyga@gmail.com - Tech Developer (5k)
 
 CRITICAL NOTES:
 - Black Ink users now use tierRawValue: "ambassador" (15k-20k range)
 - Teddy Ruks, Chaney, and Rae Sremmurd use tierRawValue: "elite" (20k+)
 - All users have isAutoFollowed: false EXCEPT James Fortune
 - Ambassador badges changed from "celebrity_crown" to "ambassador_crown"
 
 */
