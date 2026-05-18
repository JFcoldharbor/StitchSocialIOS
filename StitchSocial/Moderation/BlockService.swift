//
//  BlockService.swift
//  StitchSocial
//
//  User blocking. Writes to `users/{blockerID}/blocked/{blockedID}` so feed
//  queries can filter on the blocker's side, and `users/{blockedID}/blockedBy/{blockerID}`
//  so the blocked user's UI can hide the blocker's content too.
//
//  Replaces the stub at StitchersListView.swift:806.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class BlockService: ObservableObject {

    static let shared = BlockService()

    @Published private(set) var blockedUserIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let db = Firestore.firestore(database: "stitchfin")
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Live block list

    /// Start listening to the current user's blocked list. Call once at sign-in;
    /// `blockedUserIDs` updates reactively so feed views can filter immediately.
    func startListening() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        listener?.remove()

        listener = db.collection("users").document(userID)
            .collection("blocked")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    #if DEBUG
                    print("❌ BLOCK: Listener error — \(error.localizedDescription)")
                    #endif
                    return
                }
                let ids = Set(snapshot?.documents.map(\.documentID) ?? [])
                Task { @MainActor in
                    self.blockedUserIDs = ids
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        blockedUserIDs = []
    }

    // MARK: - Block / Unblock

    func blockUser(_ targetUserID: String) async throws {
        guard let blockerID = Auth.auth().currentUser?.uid else {
            throw BlockError.notSignedIn
        }
        guard blockerID != targetUserID else {
            throw BlockError.cannotBlockSelf
        }

        isLoading = true
        defer { isLoading = false }

        let now = Timestamp(date: Date())

        // Two-way write so both sides' UIs can filter without joins.
        let batch = db.batch()

        let blockedRef = db.collection("users").document(blockerID)
            .collection("blocked").document(targetUserID)
        batch.setData([
            "blockedUserID": targetUserID,
            "createdAt": now,
        ], forDocument: blockedRef)

        let blockedByRef = db.collection("users").document(targetUserID)
            .collection("blockedBy").document(blockerID)
        batch.setData([
            "blockerID": blockerID,
            "createdAt": now,
        ], forDocument: blockedByRef)

        try await batch.commit()

        #if DEBUG
        print("🚫 BLOCK: \(blockerID) → \(targetUserID)")
        #endif
    }

    func unblockUser(_ targetUserID: String) async throws {
        guard let blockerID = Auth.auth().currentUser?.uid else {
            throw BlockError.notSignedIn
        }

        isLoading = true
        defer { isLoading = false }

        let batch = db.batch()
        batch.deleteDocument(
            db.collection("users").document(blockerID)
                .collection("blocked").document(targetUserID)
        )
        batch.deleteDocument(
            db.collection("users").document(targetUserID)
                .collection("blockedBy").document(blockerID)
        )
        try await batch.commit()

        #if DEBUG
        print("✅ BLOCK: Unblocked \(blockerID) → \(targetUserID)")
        #endif
    }

    func isBlocked(_ userID: String) -> Bool {
        blockedUserIDs.contains(userID)
    }
}

// MARK: - Errors

enum BlockError: LocalizedError {
    case notSignedIn
    case cannotBlockSelf

    var errorDescription: String? {
        switch self {
        case .notSignedIn:    return "Sign in to block users."
        case .cannotBlockSelf: return "You can't block yourself."
        }
    }
}
