//
//  SocialSignalService.swift
//  StitchSocial
//
//  Created by James Garmon on 2/7/26.
//


//
//  SocialSignalService.swift
//  StitchSocial
//
//  Layer 4: Core Services - Social Signal / Megaphone System
//  Dependencies: FirebaseFirestore, FirebaseAuth, UserService
//  Features:
//    - Records notable engagements from Partner+ tier users
//    - Fetches active social signals for feed injection
//    - Tracks impressions (2-strike dismissal: 2 views no engagement = gone)
//    - Gates view count/watch time behind fullscreen tap + engagement
//    - Calls Cloud Function to fan out signals to engager's followers
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
class SocialSignalService: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SocialSignalService()
    
    // MARK: - Dependencies
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let functions = Functions.functions()
    
    // MARK: - Published State
    
    @Published var activeSignals: [SocialSignal] = []
    @Published var isLoading: Bool = false
    
    // MARK: - Local Cache
    
    /// Signals already dismissed this session (avoid re-fetching)
    private var dismissedSignalIDs: Set<String> = []
    
    /// Signals user already engaged with this session
    private var engagedSignalIDs: Set<String> = []
    
    // MARK: - Configuration
    
    private let maxImpressionsBeforeDismiss = 2
    private let maxSignalsPerFeedLoad = 5        // Don't flood feed
    private let signalExpirationHours: Double = 72 // Signals expire after 72 hours
    
    private init() {
        print("📢 SOCIAL SIGNAL SERVICE: Initialized")
    }
    
    // MARK: - Record Notable Engagement
    
    /// Called from EngagementManager after a Partner+ tier user hypes a video
    /// Writes the notable engagement record and triggers Cloud Function fan-out
    func recordNotableEngagement(
        engagerID: String,
        engagerName: String,
        engagerTier: String,
        engagerProfileImageURL: String?,
        videoID: String,
        videoCreatorID: String,
        hypeWeight: Int,
        cloutAwarded: Int
    ) async {
        // Only Partner+ tiers trigger the megaphone
        guard NotableEngagement.isMegaphoneTier(engagerTier) else { return }
        
        // Don't megaphone your own content
        guard engagerID != videoCreatorID else { return }
        
        print("📢 MEGAPHONE: \(engagerName) (\(engagerTier)) hyped video \(videoID) with weight \(hypeWeight)")
        
        let docID = "\(engagerID)_\(videoID)"
        
        let data: [String: Any] = [
            "id": docID,
            "engagerID": engagerID,
            "engagerName": engagerName,
            "engagerTier": engagerTier,
            "engagerProfileImageURL": engagerProfileImageURL ?? "",
            "videoID": videoID,
            "videoCreatorID": videoCreatorID,
            "hypeWeight": hypeWeight,
            "cloutAwarded": cloutAwarded,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        do {
            // Write notable engagement to video subcollection
            try await db.collection(FirebaseSchema.Collections.videos)
                .document(videoID)
                .collection("notableEngagements")
                .document(docID)
                .setData(data, merge: true)
            
            print("📢 MEGAPHONE: Notable engagement recorded")
            
            // Trigger Cloud Function to fan out to engager's followers
            try await triggerFanOut(
                engagerID: engagerID,
                engagerName: engagerName,
                engagerTier: engagerTier,
                engagerProfileImageURL: engagerProfileImageURL,
                videoID: videoID,
                videoCreatorID: videoCreatorID,
                hypeWeight: hypeWeight
            )
            
        } catch {
            print("⚠️ MEGAPHONE: Failed to record — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cloud Function Fan-Out
    
    /// Calls Cloud Function to create social signals for all of the engager's followers
    private func triggerFanOut(
        engagerID: String,
        engagerName: String,
        engagerTier: String,
        engagerProfileImageURL: String?,
        videoID: String,
        videoCreatorID: String,
        hypeWeight: Int
    ) async throws {
        
        let payload: [String: Any] = [
            "engagerID": engagerID,
            "engagerName": engagerName,
            "engagerTier": engagerTier,
            "engagerProfileImageURL": engagerProfileImageURL ?? "",
            "videoID": videoID,
            "videoCreatorID": videoCreatorID,
            "hypeWeight": hypeWeight
        ]
        
        do {
            let result = try await functions.httpsCallable("stitchnoti_fanOutSocialSignal").call(payload)
            if let data = result.data as? [String: Any],
               let followersNotified = data["followersNotified"] as? Int {
                print("📢 MEGAPHONE: Fan-out complete — \(followersNotified) followers will see this")
            }
        } catch {
            print("⚠️ MEGAPHONE: Fan-out Cloud Function failed — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load Active Signals for Feed
    
    /// Called by HomeFeedService when building feed
    /// Returns undismissed, unexpired social signals for the current user
    func loadActiveSignals(for userID: String) async -> [SocialSignal] {
        isLoading = true
        defer { isLoading = false }
        
        let cutoffDate = Date().addingTimeInterval(-signalExpirationHours * 3600)
        
        do {
            let snapshot = try await db.collection("users")
                .document(userID)
                .collection("socialSignals")
                .whereField("dismissed", isEqualTo: false)
                .whereField("engagedWith", isEqualTo: false)
                .whereField("createdAt", isGreaterThan: Timestamp(date: cutoffDate))
                .order(by: "createdAt", descending: true)
                .limit(to: maxSignalsPerFeedLoad)
                .getDocuments()
            
            var signals: [SocialSignal] = []
            
            for doc in snapshot.documents {
                let data = doc.data()
                guard !dismissedSignalIDs.contains(doc.documentID) else { continue }
                
                let signal = SocialSignal(
                    id: doc.documentID,
                    videoID: data["videoID"] as? String ?? "",
                    videoCreatorID: data["videoCreatorID"] as? String ?? "",
                    videoCreatorName: data["videoCreatorName"] as? String ?? "",
                    videoTitle: data["videoTitle"] as? String ?? "",
                    videoThumbnailURL: data["videoThumbnailURL"] as? String,
                    engagerID: data["engagerID"] as? String ?? "",
                    engagerName: data["engagerName"] as? String ?? "",
                    engagerTier: data["engagerTier"] as? String ?? "",
                    engagerProfileImageURL: data["engagerProfileImageURL"] as? String,
                    hypeWeight: data["hypeWeight"] as? Int ?? 0,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
                
                signals.append(signal)
            }
            
            activeSignals = signals
            print("📢 SOCIAL SIGNALS: Loaded \(signals.count) active signals for feed")
            return signals
            
        } catch {
            print("⚠️ SOCIAL SIGNALS: Failed to load — \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Track Impression (2-Strike Logic)
    
    /// Called when a social signal card appears in the user's feed viewport
    /// After 2 impressions with no engagement, the signal is dismissed
    func recordImpression(signalID: String, userID: String) async {
        guard !dismissedSignalIDs.contains(signalID),
              !engagedSignalIDs.contains(signalID) else { return }
        
        let docRef = db.collection("users")
            .document(userID)
            .collection("socialSignals")
            .document(signalID)
        
        do {
            try await docRef.updateData([
                "impressionCount": FieldValue.increment(Int64(1)),
                "lastImpressionAt": FieldValue.serverTimestamp()
            ])
            
            // Check if should dismiss
            let doc = try await docRef.getDocument()
            let impressions = doc.data()?["impressionCount"] as? Int ?? 0
            
            if impressions >= maxImpressionsBeforeDismiss {
                // 2 strikes — dismiss
                try await docRef.updateData(["dismissed": true])
                dismissedSignalIDs.insert(signalID)
                activeSignals.removeAll { $0.id == signalID }
                print("📢 SIGNAL DISMISSED: \(signalID) after \(impressions) impressions with no engagement")
            }
            
        } catch {
            print("⚠️ SIGNAL IMPRESSION: Failed — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Record Engagement (User Tapped In)
    
    /// Called when user taps into a social signal video (fullscreen)
    /// This stops the 2-strike clock — they engaged
    /// ONLY this counts as a real view / watch time
    func recordEngagement(signalID: String, userID: String) async {
        guard !engagedSignalIDs.contains(signalID) else { return }
        
        engagedSignalIDs.insert(signalID)
        
        let docRef = db.collection("users")
            .document(userID)
            .collection("socialSignals")
            .document(signalID)
        
        do {
            try await docRef.updateData(["engagedWith": true])
            print("📢 SIGNAL ENGAGED: \(signalID) — user tapped in, counts as real view")
        } catch {
            print("⚠️ SIGNAL ENGAGEMENT: Failed — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Get Notable Engagers for Video (UI Display)
    
    /// Returns list of notable engagers for a video's "Hyped by" section
    func getNotableEngagers(videoID: String) async -> [NotableEngagement] {
        do {
            let snapshot = try await db.collection(FirebaseSchema.Collections.videos)
                .document(videoID)
                .collection("notableEngagements")
                .order(by: "hypeWeight", descending: true)
                .limit(to: 5)
                .getDocuments()
            
            return snapshot.documents.compactMap { doc -> NotableEngagement? in
                let data = doc.data()
                return NotableEngagement(
                    id: doc.documentID,
                    engagerID: data["engagerID"] as? String ?? "",
                    engagerName: data["engagerName"] as? String ?? "",
                    engagerTier: data["engagerTier"] as? String ?? "",
                    engagerProfileImageURL: data["engagerProfileImageURL"] as? String,
                    videoID: data["videoID"] as? String ?? "",
                    videoCreatorID: data["videoCreatorID"] as? String ?? "",
                    hypeWeight: data["hypeWeight"] as? Int ?? 0,
                    cloutAwarded: data["cloutAwarded"] as? Int ?? 0,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
        } catch {
            print("⚠️ Notable engagers fetch failed — \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Cleanup
    
    func clearSessionCache() {
        dismissedSignalIDs.removeAll()
        engagedSignalIDs.removeAll()
        activeSignals.removeAll()
    }
}