//
//  CreatorCampaignService.swift
//  StitchSocial
//
//  Mode B (influencer marketplace) — service layer + Codable models.
//  Wraps the Cloud Functions deployed in StitchSocial-Functions/index.js:
//    - onCreatorCampaignCreated  (Firestore trigger, not called directly)
//    - applyToCreatorCampaign
//    - decideCreatorCampaignApplication
//    - submitCreatorCampaignDeliverable
//    - approveCreatorCampaignDeliverable
//    - createCreatorStripeOnboarding
//    - refreshCreatorStripeStatus
//    - retryHeldPayouts
//
//  Reads happen directly against Firestore. Mutations go through callables
//  so server-side auth + analytics rollups stay consistent.
//

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Models

struct CreatorCampaign: Identifiable, Codable, Hashable {
    @DocumentID var documentID: String?
    let brandID: String
    let brandName: String?
    let brandLogoURL: String?
    let title: String
    let brief: String
    let category: String?
    let payoutCents: Int
    let status: String                  // draft / open / reviewing / in_progress / completed / cancelled
    let applicationDeadline: Date?
    let contentDueDate: Date?
    let applicationsCount: Int?
    let approvedCount: Int?
    let deliveredCount: Int?
    let paidOutCount: Int?
    let criteria: CreatorCampaignCriteria?
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { documentID ?? UUID().uuidString }
    var payoutDollars: Double { Double(payoutCents) / 100.0 }
    var isOpen: Bool { status == "open" || status == "reviewing" }
}

struct CreatorCampaignCriteria: Codable, Hashable {
    let minTier: String?
    let minStitchers: Int?
    let minViewsPerVideo: Int?
    let requiredHashtags: [String]?
    let preferredCategories: [String]?
}

struct CreatorCampaignApplication: Identifiable, Codable, Hashable {
    let creatorID: String
    let creatorName: String?
    let creatorTier: String?
    let pitch: String?
    let aiFitScore: Int?
    let metricSnapshot: ApplicationMetricSnapshot?
    let status: String                  // pending / approved / rejected / withdrawn
    let appliedAt: Date?
    let decidedAt: Date?

    var id: String { creatorID }
}

struct ApplicationMetricSnapshot: Codable, Hashable {
    let stitcherCount: Int?
    let hypeRating: Double?
    let viewsPerVideoAvg: Int?
}

struct CreatorCampaignDeliverable: Identifiable, Codable, Hashable {
    let creatorID: String
    let draftURL: String?
    let notes: String?
    let draftSubmittedAt: Date?
    let approvalStatus: String          // awaiting / approved / revision_requested / rejected
    let revisionNotes: String?
    let approvedAt: Date?
    let payoutAt: Date?
    let grossAmountCents: Int?
    let platformFeeCents: Int?
    let creatorNetCents: Int?
    let stripeTransferID: String?
    let payoutStatus: String?           // paid / paid_confirmed / failed / held_no_connect_account / pending_stripe
    let payoutError: String?

    var id: String { creatorID }
}

// MARK: - Service

@MainActor
final class CreatorCampaignService: ObservableObject {

    static let shared = CreatorCampaignService()

    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let functions = Functions.functions()

    @Published var openCampaigns: [CreatorCampaign] = []
    @Published var myApplications: [CreatorCampaign] = []   // campaigns I've applied to
    @Published var brandCampaigns: [CreatorCampaign] = []
    @Published var isLoading = false

    // MARK: - Reads (creator side)

    func fetchOpenCampaigns(limit: Int = 50) async throws {
        isLoading = true
        defer { isLoading = false }

        let snap = try await db.collection("creatorCampaigns")
            .whereField("status", in: ["open", "reviewing"])
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        self.openCampaigns = snap.documents.compactMap {
            try? $0.data(as: CreatorCampaign.self)
        }
    }

    func fetchMyApplicationCampaigns(creatorID: String) async throws {
        // Application docs are subcollections — collectionGroup query gets all
        // applications across all campaigns for this creator.
        let appsSnap = try await db.collectionGroup("applications")
            .whereField("creatorID", isEqualTo: creatorID)
            .order(by: "appliedAt", descending: true)
            .limit(to: 50)
            .getDocuments()

        let campaignIDs = appsSnap.documents.compactMap { doc -> String? in
            // parent path: creatorCampaigns/{campaignID}/applications/{creatorID}
            doc.reference.parent.parent?.documentID
        }

        var campaigns: [CreatorCampaign] = []
        for id in campaignIDs {
            if let doc = try? await db.collection("creatorCampaigns").document(id).getDocument(),
               let c = try? doc.data(as: CreatorCampaign.self) {
                campaigns.append(c)
            }
        }
        self.myApplications = campaigns
    }

    func fetchApplicationStatus(campaignID: String, creatorID: String) async throws -> CreatorCampaignApplication? {
        let doc = try await db.collection("creatorCampaigns")
            .document(campaignID)
            .collection("applications")
            .document(creatorID)
            .getDocument()
        return try? doc.data(as: CreatorCampaignApplication.self)
    }

    func fetchMyDeliverable(campaignID: String, creatorID: String) async throws -> CreatorCampaignDeliverable? {
        let doc = try await db.collection("creatorCampaigns")
            .document(campaignID)
            .collection("deliverables")
            .document(creatorID)
            .getDocument()
        return try? doc.data(as: CreatorCampaignDeliverable.self)
    }

    // MARK: - Reads (brand side)

    func fetchBrandCampaigns(brandID: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let snap = try await db.collection("creatorCampaigns")
            .whereField("brandID", isEqualTo: brandID)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments()

        self.brandCampaigns = snap.documents.compactMap {
            try? $0.data(as: CreatorCampaign.self)
        }
    }

    func fetchApplications(campaignID: String) async throws -> [CreatorCampaignApplication] {
        let snap = try await db.collection("creatorCampaigns")
            .document(campaignID)
            .collection("applications")
            .order(by: "appliedAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CreatorCampaignApplication.self) }
    }

    func fetchDeliverables(campaignID: String) async throws -> [CreatorCampaignDeliverable] {
        let snap = try await db.collection("creatorCampaigns")
            .document(campaignID)
            .collection("deliverables")
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CreatorCampaignDeliverable.self) }
    }

    // MARK: - Writes (creator side)

    /// Brand creates a campaign. Triggers onCreatorCampaignCreated which
    /// embeds the brief and matches creators.
    func createCampaign(
        brandID: String,
        brandName: String,
        brandLogoURL: String?,
        title: String,
        brief: String,
        category: String?,
        payoutCents: Int,
        criteria: CreatorCampaignCriteria,
        contentDueDate: Date?
    ) async throws -> String {
        let ref = db.collection("creatorCampaigns").document()
        var data: [String: Any] = [
            "brandID": brandID,
            "brandName": brandName,
            "title": title,
            "brief": brief,
            "payoutCents": payoutCents,
            "status": "open",
            "applicationsCount": 0,
            "approvedCount": 0,
            "deliveredCount": 0,
            "paidOutCount": 0,
            "totalPayoutCents": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let category = category { data["category"] = category }
        if let brandLogoURL = brandLogoURL { data["brandLogoURL"] = brandLogoURL }
        if let due = contentDueDate { data["contentDueDate"] = Timestamp(date: due) }

        var critDict: [String: Any] = [:]
        if let v = criteria.minTier { critDict["minTier"] = v }
        if let v = criteria.minStitchers { critDict["minStitchers"] = v }
        if let v = criteria.minViewsPerVideo { critDict["minViewsPerVideo"] = v }
        if let v = criteria.requiredHashtags, !v.isEmpty { critDict["requiredHashtags"] = v }
        if let v = criteria.preferredCategories, !v.isEmpty { critDict["preferredCategories"] = v }
        data["criteria"] = critDict

        try await ref.setData(data)
        return ref.documentID
    }

    func apply(campaignID: String, pitch: String) async throws -> Int? {
        let result = try await functions.httpsCallable("applyToCreatorCampaign").call([
            "campaignID": campaignID,
            "pitch": pitch
        ])
        let payload = result.data as? [String: Any]
        return payload?["aiFitScore"] as? Int
    }

    func submitDeliverable(campaignID: String, draftURL: String, notes: String) async throws {
        _ = try await functions.httpsCallable("submitCreatorCampaignDeliverable").call([
            "campaignID": campaignID,
            "draftURL": draftURL,
            "notes": notes
        ])
    }

    // MARK: - Writes (brand side)

    func decide(campaignID: String, creatorID: String, approve: Bool) async throws {
        _ = try await functions.httpsCallable("decideCreatorCampaignApplication").call([
            "campaignID": campaignID,
            "creatorID": creatorID,
            "decision": approve ? "approved" : "rejected"
        ])
    }

    func reviewDeliverable(campaignID: String, creatorID: String, approve: Bool, revisionNotes: String = "") async throws -> [String: Any]? {
        let result = try await functions.httpsCallable("approveCreatorCampaignDeliverable").call([
            "campaignID": campaignID,
            "creatorID": creatorID,
            "approved": approve,
            "revisionNotes": revisionNotes
        ])
        return result.data as? [String: Any]
    }

    // MARK: - Stripe Connect

    struct StripeOnboardingResult {
        let onboardingURL: URL
        let stripeConnectID: String
        let isExistingAccount: Bool
    }

    struct StripeAccountStatus {
        let status: String              // none / onboarding / pending_verification / active
        let payoutsEnabled: Bool
        let chargesEnabled: Bool
        let requirements: [String]
    }

    func createStripeOnboarding() async throws -> StripeOnboardingResult {
        let result = try await functions.httpsCallable("createCreatorStripeOnboarding").call([:])
        guard let data = result.data as? [String: Any],
              let urlStr = data["onboardingURL"] as? String,
              let url = URL(string: urlStr),
              let id = data["stripeConnectID"] as? String else {
            throw NSError(domain: "Stripe", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid onboarding response"
            ])
        }
        return StripeOnboardingResult(
            onboardingURL: url,
            stripeConnectID: id,
            isExistingAccount: data["isExistingAccount"] as? Bool ?? false
        )
    }

    func refreshStripeStatus() async throws -> StripeAccountStatus {
        let result = try await functions.httpsCallable("refreshCreatorStripeStatus").call([:])
        let data = result.data as? [String: Any] ?? [:]
        return StripeAccountStatus(
            status: data["stripeAccountStatus"] as? String ?? "none",
            payoutsEnabled: data["payoutsEnabled"] as? Bool ?? false,
            chargesEnabled: data["chargesEnabled"] as? Bool ?? false,
            requirements: data["requirements"] as? [String] ?? []
        )
    }

    func retryHeldPayouts() async throws -> (succeeded: Int, failed: Int) {
        let result = try await functions.httpsCallable("retryHeldPayouts").call([:])
        let data = result.data as? [String: Any] ?? [:]
        return (
            succeeded: data["succeeded"] as? Int ?? 0,
            failed: data["failed"] as? Int ?? 0
        )
    }
}
