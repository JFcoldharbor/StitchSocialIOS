//
//  ReportService.swift
//  StitchSocial
//
//  User-facing content reporting. Submits a report to the backend `submitReport`
//  Cloud Function, which writes to the `reports` collection, increments the
//  offending user's strike counter, and auto-suspends at threshold.
//
//  Report categories mirror Stripe's restricted-content list so we can map
//  flags directly to the AUP categories Stripe asks about in their diligence.
//

import Foundation
import FirebaseFunctions
import FirebaseAuth

// MARK: - Report Reason

/// Reportable categories. The raw values are the Firestore enum values; the
/// `displayName` is the human-readable label shown in the report sheet.
enum ReportReason: String, CaseIterable, Identifiable {
    case adult              // nudity / explicit sexual content
    case violence           // graphic violence, gore, self-harm
    case hate               // hate speech, hate symbols, harassment
    case ipInfringement     // copyright, trademark, leaked content
    case spam               // spam, scams, misleading
    case impersonation      // pretending to be someone else
    case minorSafety        // CSAM / underage user (escalated path)
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adult:           return "Nudity or sexual content"
        case .violence:        return "Violence or self-harm"
        case .hate:            return "Hate speech or harassment"
        case .ipInfringement:  return "Copyright or IP infringement"
        case .spam:            return "Spam or scam"
        case .impersonation:   return "Impersonation"
        case .minorSafety:     return "Child safety concern"
        case .other:           return "Something else"
        }
    }

    var iconName: String {
        switch self {
        case .adult:          return "eye.slash"
        case .violence:       return "exclamationmark.triangle"
        case .hate:           return "hand.raised.slash"
        case .ipInfringement: return "doc.badge.gearshape"
        case .spam:           return "tray.full"
        case .impersonation:  return "person.crop.circle.badge.questionmark"
        case .minorSafety:    return "shield.lefthalf.filled"
        case .other:          return "ellipsis.circle"
        }
    }
}

// MARK: - Report Target

/// What's being reported. `videoID` and `userID` cover the two surfaces users
/// will see Report buttons on. Server expands as needed (comments, threads).
enum ReportTargetType: String {
    case video
    case user
}

// MARK: - Service

@MainActor
final class ReportService: ObservableObject {

    static let shared = ReportService()

    @Published private(set) var isSubmitting = false
    @Published private(set) var lastError: String?

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    /// Submit a report. Backend handles idempotency on (reporterID, targetID, reason)
    /// so spam-tapping the same button doesn't inflate strike counts.
    func submitReport(
        targetType: ReportTargetType,
        targetID: String,
        offendingUserID: String,
        reason: ReportReason,
        details: String? = nil
    ) async throws {
        guard Auth.auth().currentUser != nil else {
            throw ReportError.notSignedIn
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let payload: [String: Any] = [
            "targetType": targetType.rawValue,
            "targetID": targetID,
            "offendingUserID": offendingUserID,
            "reason": reason.rawValue,
            "details": details ?? "",
        ]

        do {
            _ = try await functions.httpsCallable("submitReport").call(payload)
            #if DEBUG
            print("🚩 REPORT: Submitted (\(reason.rawValue)) for \(targetType.rawValue):\(targetID)")
            #endif
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            print("❌ REPORT: Submission failed — \(error)")
            #endif
            throw ReportError.submissionFailed(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum ReportError: LocalizedError {
    case notSignedIn
    case submissionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to report content."
        case .submissionFailed(let reason):
            return "Couldn't submit report: \(reason)"
        }
    }
}
