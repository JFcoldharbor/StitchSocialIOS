//
//  DiscoverySignal.swift
//  StitchSocial
//
//  Created by James Garmon on 2/7/26.
//


//
//  DiscoveryEngagementTracker.swift
//  StitchSocial
//
//  Layer 6: Coordination - Passive Discovery Engagement Tracking
//  Tracks watch time, session intent, rewatch caps, and creator preference scoring
//  from discovery swipe cards WITHOUT any explicit user buttons.
//
//  Signal Logic:
//    Watch time hype weights: 3s = 1, 5s = 2, 8s = 3, fullscreen tap = strong hype
//    Cool-down: < 3s + swipe away = negative signal
//    Rewatch cap: max 2x per video (manual swipe-back only, not loops)
//    Session intent: signals only count if user has made at least 1 manual interaction
//    Auto-progress only sessions generate ZERO algorithm data
//
//  Creator Preference Tiers (from accumulated signals):
//    1 cool-down signal = reduce video push in discovery
//    2-4 cool-downs on same creator = escalating suppression, signals decay over time
//    After 4th cool-down = enforce delay before 5th registers (prevent accidental perma-suppress)
//    5+ cool-downs on same creator across videos = never show in discovery
//    Following a creator overrides ALL cool-down signals (content shows in home feed normally)
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Discovery Signal Types

/// A single passive engagement signal from discovery card viewing
struct DiscoverySignal {
    let videoID: String
    let creatorID: String
    let watchTimeSeconds: TimeInterval
    let didTapFullscreen: Bool
    let wasManualSwipe: Bool       // true = user swiped, false = auto-advanced
    let wasSwipeBack: Bool         // true = user swiped back to rewatch
    let timestamp: Date
    
    /// Calculated hype weight from watch time
    var hypeWeight: Int {
        if didTapFullscreen { return 4 }
        if watchTimeSeconds >= 8 { return 3 }
        if watchTimeSeconds >= 5 { return 2 }
        if watchTimeSeconds >= 3 { return 1 }
        return 0
    }
    
    /// Whether this counts as a cool-down signal
    var isCoolSignal: Bool {
        return watchTimeSeconds < 3 && wasManualSwipe && !didTapFullscreen
    }
}

// MARK: - Creator Preference Level

enum CreatorPreference: Int, Codable {
    case neutral = 0          // Default — no signals yet
    case mildBoost = 1        // Some hype signals
    case strongBoost = 2      // Repeated hype signals across videos
    case superFan = 3         // 5+ strong hype signals — prioritize heavily
    case mildSuppress = -1    // 1 cool-down signal
    case moderateSuppress = -2 // 2-4 cool-downs
    case strongSuppress = -3  // 4 cool-downs (decay active, delay before 5th)
    case blocked = -4         // 5+ cool-downs across multiple videos — never show
    
    var shouldShowInDiscovery: Bool {
        return self != .blocked
    }
    
    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .mildBoost: return "Mild Boost"
        case .strongBoost: return "Strong Boost"
        case .superFan: return "Super Fan"
        case .mildSuppress: return "Mild Suppress"
        case .moderateSuppress: return "Moderate Suppress"
        case .strongSuppress: return "Strong Suppress"
        case .blocked: return "Blocked"
        }
    }
}

// MARK: - Video Watch Record (per-video tracking)

struct VideoWatchRecord {
    let videoID: String
    let creatorID: String
    var watchCount: Int = 0           // How many times this video was viewed (capped at 2)
    var totalHypeWeight: Int = 0      // Accumulated hype weight (capped at 2x max)
    var coolSignalCount: Int = 0      // Number of cool-down signals
    var didTapFullscreen: Bool = false
    var lastWatchedAt: Date = Date()
    
    /// Max hype weight from a single watch is 4 (fullscreen tap), x2 for rewatch = 8
    var maxHypeWeight: Int { return 8 }
    
    var isRewatchCapped: Bool {
        return watchCount >= 2
    }
}

// MARK: - Creator Signal Accumulator

struct CreatorSignalAccumulator: Codable {
    let creatorID: String
    var totalHypeWeight: Int = 0
    var totalCoolSignals: Int = 0
    var videosWithCoolSignals: Int = 0    // Unique videos where cool was registered
    var videosWithHypeSignals: Int = 0    // Unique videos where hype was registered
    var lastCoolSignalAt: Date?
    var lastHypeSignalAt: Date?
    var coolDelayActive: Bool = false      // After 4th cool, delay is enforced
    var coolDelayStartedAt: Date?
    var preference: CreatorPreference = .neutral
    
    /// Delay duration required between 4th and 5th cool-down tap
    static let coolDelayDuration: TimeInterval = 3.0
    
    /// Decay window — cool signals older than this fade
    static let coolDecayWindow: TimeInterval = 14 * 24 * 60 * 60 // 14 days
    
    /// Can register the 5th (permanent) cool signal?
    var canRegisterBlockingCool: Bool {
        guard coolDelayActive, let started = coolDelayStartedAt else { return false }
        return Date().timeIntervalSince(started) >= CreatorSignalAccumulator.coolDelayDuration
    }
    
    /// Recalculate preference based on current signal state
    mutating func recalculatePreference() {
        // Cool-down takes priority
        if totalCoolSignals >= 5 && videosWithCoolSignals >= 2 {
            preference = .blocked
        } else if totalCoolSignals >= 4 {
            preference = .strongSuppress
            // Activate delay before allowing 5th
            if !coolDelayActive {
                coolDelayActive = true
                coolDelayStartedAt = Date()
            }
        } else if totalCoolSignals >= 2 {
            preference = .moderateSuppress
        } else if totalCoolSignals == 1 {
            preference = .mildSuppress
        }
        // Hype side (only if no cool signals override)
        else if totalHypeWeight >= 20 && videosWithHypeSignals >= 3 {
            preference = .superFan
        } else if totalHypeWeight >= 10 && videosWithHypeSignals >= 2 {
            preference = .strongBoost
        } else if totalHypeWeight >= 3 {
            preference = .mildBoost
        } else {
            preference = .neutral
        }
    }
    
    /// Apply decay to cool signals older than the decay window
    mutating func applyDecay() {
        guard let lastCool = lastCoolSignalAt else { return }
        let timeSinceLastCool = Date().timeIntervalSince(lastCool)
        
        // Only decay signals below the 5th-tap threshold
        if timeSinceLastCool > CreatorSignalAccumulator.coolDecayWindow && totalCoolSignals < 5 {
            // Reduce cool signals by 1 for each decay period passed
            let decayPeriods = Int(timeSinceLastCool / CreatorSignalAccumulator.coolDecayWindow)
            let decayAmount = min(decayPeriods, totalCoolSignals)
            totalCoolSignals = max(0, totalCoolSignals - decayAmount)
            
            // Reset delay state if we decayed below threshold
            if totalCoolSignals < 4 {
                coolDelayActive = false
                coolDelayStartedAt = nil
            }
            
            recalculatePreference()
        }
    }
}

// MARK: - Discovery Engagement Tracker

@MainActor
class DiscoveryEngagementTracker: ObservableObject {
    
    // MARK: - Singleton
    static let shared = DiscoveryEngagementTracker()
    
    // MARK: - Published State
    @Published var sessionHasIntent: Bool = false
    @Published var creatorPreferences: [String: CreatorPreference] = [:]
    
    // MARK: - Internal State
    
    /// Tracks whether user has done ANY manual interaction this session
    private var manualInteractionCount: Int = 0
    
    /// Per-video watch records (keyed by videoID)
    private var videoRecords: [String: VideoWatchRecord] = [:]
    
    /// Per-creator signal accumulators (keyed by creatorID)
    private var creatorAccumulators: [String: CreatorSignalAccumulator] = [:]
    
    /// Videos that were cool-signaled per creator (to track unique video count)
    private var creatorCoolVideoSets: [String: Set<String>] = [:]
    private var creatorHypeVideoSets: [String: Set<String>] = [:]
    
    /// Current card start time (for measuring watch duration)
    private var currentCardStartTime: Date?
    private var currentCardVideoID: String?
    private var currentCardCreatorID: String?
    
    // MARK: - Firebase
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    // MARK: - Initialization
    
    private init() {
        print("📊 DISCOVERY TRACKER: Initialized")
    }
    
    // MARK: - Session Intent Detection
    
    /// Call when user performs ANY manual interaction (swipe, tap, swipe-back)
    func registerManualInteraction() {
        manualInteractionCount += 1
        if !sessionHasIntent {
            sessionHasIntent = true
            print("📊 DISCOVERY TRACKER: Session intent confirmed (manual interaction detected)")
        }
    }
    
    /// Reset session tracking (call when discovery view appears)
    func startNewSession() {
        manualInteractionCount = 0
        sessionHasIntent = false
        videoRecords.removeAll()
        currentCardStartTime = nil
        currentCardVideoID = nil
        currentCardCreatorID = nil
        print("📊 DISCOVERY TRACKER: New session started")
    }
    
    // MARK: - Card Lifecycle
    
    /// Call when a new card becomes the active (top) card
    func cardBecameActive(videoID: String, creatorID: String) {
        // Finalize previous card if any
        finalizeCurrentCard(wasManualSwipe: false, wasAutoAdvance: true)
        
        currentCardStartTime = Date()
        currentCardVideoID = videoID
        currentCardCreatorID = creatorID
    }
    
    /// Call when user manually swipes to next card
    func cardSwipedAway(wasSwipeBack: Bool = false) {
        registerManualInteraction()
        finalizeCurrentCard(wasManualSwipe: true, wasAutoAdvance: false, wasSwipeBack: wasSwipeBack)
    }
    
    /// Call when card auto-advances (loop count reached)
    func cardAutoAdvanced() {
        finalizeCurrentCard(wasManualSwipe: false, wasAutoAdvance: true)
    }
    
    /// Call when user taps a card to go fullscreen
    func cardTappedFullscreen(videoID: String, creatorID: String) {
        registerManualInteraction()
        
        guard sessionHasIntent else { return }
        
        // Record fullscreen tap
        var record = videoRecords[videoID] ?? VideoWatchRecord(videoID: videoID, creatorID: creatorID)
        record.didTapFullscreen = true
        videoRecords[videoID] = record
        
        // Process as strong hype signal
        let signal = DiscoverySignal(
            videoID: videoID,
            creatorID: creatorID,
            watchTimeSeconds: 99, // Fullscreen = max watch
            didTapFullscreen: true,
            wasManualSwipe: true,
            wasSwipeBack: false,
            timestamp: Date()
        )
        
        processSignal(signal)
        print("📊 DISCOVERY TRACKER: Fullscreen tap — videoID=\(videoID.prefix(8)), hypeWeight=4")
    }
    
    // MARK: - Signal Processing
    
    private func finalizeCurrentCard(wasManualSwipe: Bool, wasAutoAdvance: Bool, wasSwipeBack: Bool = false) {
        guard let videoID = currentCardVideoID,
              let creatorID = currentCardCreatorID,
              let startTime = currentCardStartTime else { return }
        
        let watchTime = Date().timeIntervalSince(startTime)
        
        // Clear current card tracking
        currentCardStartTime = nil
        currentCardVideoID = nil
        currentCardCreatorID = nil
        
        // If session has no intent (all auto-progress, no touches), skip everything
        guard sessionHasIntent else { return }
        
        // If this was auto-advance with no manual interaction, skip
        if wasAutoAdvance && !wasManualSwipe { return }
        
        // Check rewatch cap
        var record = videoRecords[videoID] ?? VideoWatchRecord(videoID: videoID, creatorID: creatorID)
        
        if wasSwipeBack {
            // This is a rewatch — check cap
            guard !record.isRewatchCapped else {
                print("📊 DISCOVERY TRACKER: Rewatch capped for videoID=\(videoID.prefix(8))")
                return
            }
        }
        
        record.watchCount += 1
        record.lastWatchedAt = Date()
        
        let signal = DiscoverySignal(
            videoID: videoID,
            creatorID: creatorID,
            watchTimeSeconds: watchTime,
            didTapFullscreen: false,
            wasManualSwipe: wasManualSwipe,
            wasSwipeBack: wasSwipeBack,
            timestamp: Date()
        )
        
        // Apply hype weight with rewatch cap
        let weight = signal.hypeWeight
        let newTotal = record.totalHypeWeight + weight
        record.totalHypeWeight = min(newTotal, record.maxHypeWeight)
        
        if signal.isCoolSignal {
            record.coolSignalCount += 1
        }
        
        videoRecords[videoID] = record
        
        processSignal(signal)
    }
    
    private func processSignal(_ signal: DiscoverySignal) {
        let creatorID = signal.creatorID
        
        var accumulator = creatorAccumulators[creatorID] ?? CreatorSignalAccumulator(creatorID: creatorID)
        
        // Apply decay first
        accumulator.applyDecay()
        
        if signal.isCoolSignal {
            // Cool-down signal
            
            // Check if 5th cool needs delay enforcement
            if accumulator.totalCoolSignals >= 4 && accumulator.coolDelayActive {
                guard accumulator.canRegisterBlockingCool else {
                    print("📊 DISCOVERY TRACKER: Cool delay active — 5th signal blocked (wait \(String(format: "%.1f", CreatorSignalAccumulator.coolDelayDuration))s)")
                    return
                }
            }
            
            accumulator.totalCoolSignals += 1
            accumulator.lastCoolSignalAt = Date()
            
            // Track unique videos
            var coolSet = creatorCoolVideoSets[creatorID] ?? Set<String>()
            coolSet.insert(signal.videoID)
            creatorCoolVideoSets[creatorID] = coolSet
            accumulator.videosWithCoolSignals = coolSet.count
            
            print("📊 DISCOVERY TRACKER: Cool signal — creator=\(creatorID.prefix(8)), total=\(accumulator.totalCoolSignals), uniqueVideos=\(coolSet.count)")
            
        } else if signal.hypeWeight > 0 {
            // Hype signal
            accumulator.totalHypeWeight += signal.hypeWeight
            accumulator.lastHypeSignalAt = Date()
            
            // Track unique videos
            var hypeSet = creatorHypeVideoSets[creatorID] ?? Set<String>()
            hypeSet.insert(signal.videoID)
            creatorHypeVideoSets[creatorID] = hypeSet
            accumulator.videosWithHypeSignals = hypeSet.count
            
            print("📊 DISCOVERY TRACKER: Hype signal — creator=\(creatorID.prefix(8)), weight=\(signal.hypeWeight), totalWeight=\(accumulator.totalHypeWeight)")
        }
        
        accumulator.recalculatePreference()
        creatorAccumulators[creatorID] = accumulator
        creatorPreferences[creatorID] = accumulator.preference
        
        // Persist to Firebase periodically
        persistIfNeeded(creatorID: creatorID, accumulator: accumulator)
    }
    
    // MARK: - Query Helpers
    
    /// Check if a creator should appear in discovery for this user
    func shouldShowCreator(_ creatorID: String) -> Bool {
        guard let pref = creatorPreferences[creatorID] else { return true }
        return pref.shouldShowInDiscovery
    }
    
    /// Get discovery weight multiplier for a creator (for sorting/ranking)
    func discoveryWeight(for creatorID: String) -> Double {
        guard let pref = creatorPreferences[creatorID] else { return 1.0 }
        
        switch pref {
        case .superFan: return 3.0
        case .strongBoost: return 2.0
        case .mildBoost: return 1.5
        case .neutral: return 1.0
        case .mildSuppress: return 0.5
        case .moderateSuppress: return 0.2
        case .strongSuppress: return 0.1
        case .blocked: return 0.0
        }
    }
    
    /// Get all blocked creator IDs (for filtering discovery queries)
    func blockedCreatorIDs() -> Set<String> {
        return Set(creatorPreferences.filter { $0.value == .blocked }.keys)
    }
    
    /// Get boosted creator IDs (for prioritizing in discovery)
    func boostedCreatorIDs() -> [(String, Double)] {
        return creatorPreferences
            .filter { $0.value.rawValue > 0 }
            .map { ($0.key, discoveryWeight(for: $0.key)) }
            .sorted { $0.1 > $1.1 }
    }
    
    // MARK: - Firebase Persistence
    
    private var pendingPersists: Set<String> = []
    private var persistTask: Task<Void, Never>?
    
    private func persistIfNeeded(creatorID: String, accumulator: CreatorSignalAccumulator) {
        pendingPersists.insert(creatorID)
        
        // Batch persists — wait 5 seconds then write all pending
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await flushPendingPersists()
        }
    }
    
    private func flushPendingPersists() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        let creatorsToFlush = pendingPersists
        pendingPersists.removeAll()
        
        for creatorID in creatorsToFlush {
            guard let accumulator = creatorAccumulators[creatorID] else { continue }
            
            let docRef = db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("discoveryPreferences")
                .document(creatorID)
            
            let data: [String: Any] = [
                "creatorID": creatorID,
                "totalHypeWeight": accumulator.totalHypeWeight,
                "totalCoolSignals": accumulator.totalCoolSignals,
                "videosWithCoolSignals": accumulator.videosWithCoolSignals,
                "videosWithHypeSignals": accumulator.videosWithHypeSignals,
                "preference": accumulator.preference.rawValue,
                "coolDelayActive": accumulator.coolDelayActive,
                "updatedAt": Timestamp()
            ]
            
            batch.setData(data, forDocument: docRef, merge: true)
        }
        
        do {
            try await batch.commit()
            print("📊 DISCOVERY TRACKER: Persisted \(creatorsToFlush.count) creator preferences")
        } catch {
            print("⚠️ DISCOVERY TRACKER: Persist failed — \(error.localizedDescription)")
            // Re-queue failed persists
            pendingPersists.formUnion(creatorsToFlush)
        }
    }
    
    // MARK: - Load Preferences from Firebase
    
    func loadPreferences() async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection(FirebaseSchema.Collections.users)
                .document(userID)
                .collection("discoveryPreferences")
                .getDocuments()
            
            for doc in snapshot.documents {
                let data = doc.data()
                let creatorID = data["creatorID"] as? String ?? doc.documentID
                let prefRaw = data["preference"] as? Int ?? 0
                
                if let pref = CreatorPreference(rawValue: prefRaw) {
                    creatorPreferences[creatorID] = pref
                    
                    // Rebuild accumulator
                    var acc = CreatorSignalAccumulator(creatorID: creatorID)
                    acc.totalHypeWeight = data["totalHypeWeight"] as? Int ?? 0
                    acc.totalCoolSignals = data["totalCoolSignals"] as? Int ?? 0
                    acc.videosWithCoolSignals = data["videosWithCoolSignals"] as? Int ?? 0
                    acc.videosWithHypeSignals = data["videosWithHypeSignals"] as? Int ?? 0
                    acc.coolDelayActive = data["coolDelayActive"] as? Bool ?? false
                    acc.preference = pref
                    creatorAccumulators[creatorID] = acc
                }
            }
            
            print("📊 DISCOVERY TRACKER: Loaded \(creatorPreferences.count) creator preferences")
        } catch {
            print("⚠️ DISCOVERY TRACKER: Failed to load preferences — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cleanup
    
    func flushOnExit() {
        Task {
            await flushPendingPersists()
        }
    }
}