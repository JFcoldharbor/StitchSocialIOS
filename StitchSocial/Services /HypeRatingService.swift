//
//  HypeRatingService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Hype Rating Regeneration & Management
//  Contains: HypeRegenSource enum, HypeRatingState struct, HypeRatingService class
//
//  ALL IN ONE FILE — do not split. Delete any separate HypeRegenSource.swift file.
//
//  Hype Rating is a 0–100% engagement budget that drains when users engage
//  and regenerates through platform activity:
//
//  Regeneration Sources (highest to lowest):
//    1. Receiving hype on your content        → strongest regen
//    2. Getting stitches/replies on threads    → strong regen
//    3. Posting original in-app content        → moderate regen
//    4. Stitching/replying to someone else     → small regen
//    5. Passive time decay                     → 30% return over 7 days (floor)
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Hype Rating Regeneration Event

enum HypeRegenSource: String, Codable {
    case receivedHype
    case receivedStitch
    case receivedReply
    case postedOriginal
    case postedCameraRoll
    case stitchedOther
    case repliedToOther
    case passiveTime
    case referralBonus
    
    var baseRegenAmount: Double {
        switch self {
        case .receivedHype:       return 1.5
        case .receivedStitch:     return 3.0
        case .receivedReply:      return 2.0
        case .postedOriginal:     return 4.0
        case .postedCameraRoll:   return 1.5
        case .stitchedOther:      return 2.0
        case .repliedToOther:     return 1.5
        case .passiveTime:        return 0.0
        case .referralBonus:      return 2.0
        }
    }
    
    var diminishingFactor: Double {
        switch self {
        case .receivedHype:       return 0.95
        case .receivedStitch:     return 0.90
        case .receivedReply:      return 0.90
        case .postedOriginal:     return 0.60
        case .postedCameraRoll:   return 0.40
        case .stitchedOther:      return 0.70
        case .repliedToOther:     return 0.70
        case .passiveTime:        return 1.0
        case .referralBonus:      return 1.0
        }
    }
    
    var dailyCap: Int {
        switch self {
        case .receivedHype:       return 50
        case .receivedStitch:     return 20
        case .receivedReply:      return 30
        case .postedOriginal:     return 5
        case .postedCameraRoll:   return 3
        case .stitchedOther:      return 10
        case .repliedToOther:     return 15
        case .passiveTime:        return 1
        case .referralBonus:      return 10
        }
    }
}

// MARK: - Hype Rating State (Persisted)

struct HypeRatingState: Codable {
    var currentRating: Double
    var lastUpdatedAt: Date
    var lastPassiveRegenAt: Date
    var dailyEventCounts: [String: Int]
    var dailyCountsResetAt: Date
    var lastFullAt: Date?
    var pendingRegenFromEngagement: Double
    
    init() {
        self.currentRating = 25.0
        self.lastUpdatedAt = Date()
        self.lastPassiveRegenAt = Date()
        self.dailyEventCounts = [:]
        self.dailyCountsResetAt = Date()
        self.lastFullAt = nil
        self.pendingRegenFromEngagement = 0.0
    }
    
    // 30% over 168 hours (7 days) = ~0.1786% per hour
    mutating func calculatePassiveRegen() -> Double {
        let now = Date()
        let hoursSinceLastRegen = now.timeIntervalSince(lastPassiveRegenAt) / 3600.0
        guard hoursSinceLastRegen >= 1.0 else { return 0 }
        
        let passiveRatePerHour = 30.0 / 168.0
        let passiveRegen = hoursSinceLastRegen * passiveRatePerHour
        let capped = min(passiveRegen, 30.0)
        
        lastPassiveRegenAt = now
        return capped
    }
    
    mutating func resetDailyCountsIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDate(dailyCountsResetAt, inSameDayAs: Date()) {
            dailyEventCounts.removeAll()
            dailyCountsResetAt = Date()
        }
    }
    
    mutating func canRegisterEvent(_ source: HypeRegenSource) -> Bool {
        resetDailyCountsIfNeeded()
        let count = dailyEventCounts[source.rawValue, default: 0]
        return count < source.dailyCap
    }
    
    mutating func registerEvent(_ source: HypeRegenSource) {
        resetDailyCountsIfNeeded()
        dailyEventCounts[source.rawValue, default: 0] += 1
    }
    
    func diminishedReward(for source: HypeRegenSource) -> Double {
        let count = dailyEventCounts[source.rawValue, default: 0]
        return source.baseRegenAmount * pow(source.diminishingFactor, Double(count))
    }
}

// MARK: - Hype Rating Service

@MainActor
class HypeRatingService: ObservableObject {
    
    static let shared = HypeRatingService()
    
    @Published var currentRating: Double = 25.0
    @Published var isLoaded: Bool = false
    
    private var state = HypeRatingState()
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private var saveTask: Task<Void, Never>?
    private let maxRating: Double = 100.0
    private let minRating: Double = 0.0
    
    private init() {
        print("⚡ HYPE RATING SERVICE: Initialized")
    }
    
    // MARK: - Load
    
    func loadRating() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("hypeRating")
                .document("state")
                .getDocument()
            
            if doc.exists, let data = doc.data() {
                state.currentRating = data["currentRating"] as? Double ?? 25.0
                if let ts = data["lastUpdatedAt"] as? Timestamp { state.lastUpdatedAt = ts.dateValue() }
                if let ts = data["lastPassiveRegenAt"] as? Timestamp { state.lastPassiveRegenAt = ts.dateValue() }
                if let dc = data["dailyEventCounts"] as? [String: Int] { state.dailyEventCounts = dc }
                if let ts = data["dailyCountsResetAt"] as? Timestamp { state.dailyCountsResetAt = ts.dateValue() }
                if let p = data["pendingRegenFromEngagement"] as? Double { state.pendingRegenFromEngagement = p }
                
                let passiveRegen = state.calculatePassiveRegen()
                if passiveRegen > 0 {
                    state.currentRating = min(maxRating, state.currentRating + passiveRegen)
                    print("⚡ HYPE RATING: +\(String(format: "%.1f", passiveRegen))% passive regen")
                }
                
                if state.pendingRegenFromEngagement > 0 {
                    state.currentRating = min(maxRating, state.currentRating + state.pendingRegenFromEngagement)
                    print("⚡ HYPE RATING: +\(String(format: "%.1f", state.pendingRegenFromEngagement))% pending engagement regen")
                    state.pendingRegenFromEngagement = 0
                }
                
                currentRating = state.currentRating
                isLoaded = true
                scheduleSave()
                print("⚡ HYPE RATING: Loaded \(String(format: "%.1f", currentRating))%")
            } else {
                state = HypeRatingState()
                currentRating = state.currentRating
                isLoaded = true
                await saveToFirebase()
                print("⚡ HYPE RATING: Initialized at \(String(format: "%.1f", currentRating))%")
            }
        } catch {
            print("⚠️ HYPE RATING: Failed to load — \(error.localizedDescription)")
            currentRating = state.currentRating
            isLoaded = true
        }
    }
    
    // MARK: - Deduct
    
    func deductRating(_ cost: Double) {
        state.currentRating = max(minRating, state.currentRating - cost)
        state.lastUpdatedAt = Date()
        currentRating = state.currentRating
        scheduleSave()
    }
    
    func canAfford(_ cost: Double) -> Bool {
        return state.currentRating >= cost
    }
    
    /// Restore optimistically deducted rating when server rejects engagement
    func restoreRating(_ amount: Double) {
        state.currentRating = min(maxRating, state.currentRating + amount)
        state.lastUpdatedAt = Date()
        currentRating = state.currentRating
        print("⚡ HYPE RATING: Restored +\(String(format: "%.2f", amount))% (server rejected) → \(String(format: "%.1f", currentRating))%")
        scheduleSave()
    }
    
    // MARK: - Activity Regen Triggers
    
    func receivedHypeOnContent()                { applyRegen(source: .receivedHype) }
    func receivedStitchOnContent()              { applyRegen(source: .receivedStitch) }
    func receivedReplyOnContent()               { applyRegen(source: .receivedReply) }
    func didPostOriginalContent(isInApp: Bool)  { applyRegen(source: isInApp ? .postedOriginal : .postedCameraRoll) }
    func didStitchContent()                     { applyRegen(source: .stitchedOther) }
    func didReplyToContent()                    { applyRegen(source: .repliedToOther) }
    func applyReferralBonus()                   { applyRegen(source: .referralBonus) }
    
    // MARK: - Core Regen
    
    private func applyRegen(source: HypeRegenSource) {
        guard state.canRegisterEvent(source) else {
            print("⚡ HYPE RATING: Daily cap reached for \(source.rawValue)")
            return
        }
        
        let reward = state.diminishedReward(for: source)
        state.registerEvent(source)
        guard reward > 0.01 else { return }
        
        let oldRating = state.currentRating
        state.currentRating = min(maxRating, state.currentRating + reward)
        state.lastUpdatedAt = Date()
        currentRating = state.currentRating
        
        if state.currentRating >= maxRating {
            state.lastFullAt = Date()
        }
        
        print("⚡ HYPE RATING: +\(String(format: "%.2f", reward))% from \(source.rawValue) → \(String(format: "%.1f", oldRating))% → \(String(format: "%.1f", currentRating))%")
        scheduleSave()
    }
    
    func refreshPassiveRegen() {
        let passiveRegen = state.calculatePassiveRegen()
        guard passiveRegen > 0.1 else { return }
        
        state.currentRating = min(maxRating, state.currentRating + passiveRegen)
        state.lastUpdatedAt = Date()
        currentRating = state.currentRating
        print("⚡ HYPE RATING: Passive +\(String(format: "%.1f", passiveRegen))% → \(String(format: "%.1f", currentRating))%")
        scheduleSave()
    }
    
    // MARK: - Persistence
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await saveToFirebase()
        }
    }
    
    private func saveToFirebase() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "currentRating": state.currentRating,
            "lastUpdatedAt": Timestamp(date: state.lastUpdatedAt),
            "lastPassiveRegenAt": Timestamp(date: state.lastPassiveRegenAt),
            "dailyEventCounts": state.dailyEventCounts,
            "dailyCountsResetAt": Timestamp(date: state.dailyCountsResetAt),
            "pendingRegenFromEngagement": state.pendingRegenFromEngagement
        ]
        
        do {
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("hypeRating")
                .document("state")
                .setData(data, merge: true)
        } catch {
            print("⚠️ HYPE RATING: Save failed — \(error.localizedDescription)")
        }
    }
    
    func flushOnExit() {
        Task { await saveToFirebase() }
    }
    
    // MARK: - Queue Regen for Offline Creators
    
    func queueEngagementRegen(source: HypeRegenSource, amount: Double) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        do {
            try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("hypeRating")
                .document("state")
                .setData([
                    "pendingRegenFromEngagement": FieldValue.increment(amount)
                ], merge: true)
        } catch {
            print("⚠️ HYPE RATING: Failed to queue regen — \(error.localizedDescription)")
        }
    }
}
