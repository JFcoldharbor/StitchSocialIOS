import SwiftUI
import FirebaseFunctions

// MARK: - ReportSheetView
//
// Presented when the user taps "Report" on a video or profile. Collects the
// reason category + optional note, then calls the `submitReport` Cloud
// Function (defined in StitchSocial-Functions/index.js).
//
// Server-side, submitReport:
//   - validates the report
//   - writes to the `reports` Firestore collection
//   - increments the offender's strike counter
//   - auto-suspends at REPORT_STRIKE_THRESHOLD (5)
//
// This sheet is the *human-flagging* counterpart to the AWS Rekognition
// automated moderation pipeline (moderateNewVideo). Rekognition catches
// what AI can see; this catches what only people can — harassment, IP
// infringement, impersonation, hate speech context, etc.
//

struct ReportSheetView: View {
    let targetType: String   // "video" | "user"
    let targetID: String
    let onDismiss: () -> Void

    @State private var selectedReason: ReportReason? = nil
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil
    @State private var showSuccessToast: Bool = false

    private let functions = Functions.functions()

    enum ReportReason: String, CaseIterable, Identifiable {
        case adult            // adult / sexual content
        case violence         // graphic violence
        case hate             // hate speech / extremism
        case ipInfringement   // copyright / trademark
        case spam             // spam / scam
        case impersonation    // impersonating someone
        case minorSafety      // child safety violation
        case other            // anything else

        var id: String { rawValue }

        var label: String {
            switch self {
            case .adult:          return "Nudity or sexual content"
            case .violence:       return "Graphic violence"
            case .hate:           return "Hate speech or extremism"
            case .ipInfringement: return "Copyright or trademark"
            case .spam:           return "Spam or scam"
            case .impersonation:  return "Impersonation"
            case .minorSafety:    return "Child safety violation"
            case .other:          return "Something else"
            }
        }

        var icon: String {
            switch self {
            case .adult:          return "exclamationmark.shield.fill"
            case .violence:       return "exclamationmark.triangle.fill"
            case .hate:           return "person.2.slash.fill"
            case .ipInfringement: return "doc.badge.gearshape.fill"
            case .spam:           return "envelope.badge.shield.half.filled"
            case .impersonation:  return "person.crop.circle.badge.exclamationmark"
            case .minorSafety:    return "shield.lefthalf.filled"
            case .other:          return "flag.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("What's the issue?")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.top, 12)

                        Text("Our team reviews every report. False reports can affect your standing.")
                            .font(.footnote)
                            .foregroundColor(.gray)

                        VStack(spacing: 8) {
                            ForEach(ReportReason.allCases) { reason in
                                Button {
                                    selectedReason = reason
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: reason.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedReason == reason ? .black : .white)
                                            .frame(width: 28)
                                        Text(reason.label)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(selectedReason == reason ? .black : .white)
                                        Spacer()
                                        if selectedReason == reason {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.black)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(selectedReason == reason ? Color.white : Color.white.opacity(0.08))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if selectedReason != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add context (optional)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.gray)
                                TextEditor(text: $note)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(10)
                                    .frame(minHeight: 80, maxHeight: 140)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .overlay(alignment: .topLeading) {
                                        if note.isEmpty {
                                            Text("What should we know?")
                                                .foregroundColor(.gray.opacity(0.6))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 12)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                Text("\(note.count) / 1000")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .transition(.opacity)
                        }

                        if let submitError {
                            Text(submitError)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .padding(.vertical, 6)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.black)
                                }
                                Text(isSubmitting ? "Sending…" : "Submit report")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedReason != nil ? Color.white : Color.gray.opacity(0.3))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        .disabled(selectedReason == nil || isSubmitting)

                        Text("If someone is in immediate danger, contact local emergency services. For DMCA takedowns, email dmca@stitchsocial.me.")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay(alignment: .top) {
                if showSuccessToast {
                    Text("Report sent. Thanks for keeping Stitch safe.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.9))
                        .cornerRadius(20)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private func submit() async {
        guard let reason = selectedReason else { return }
        isSubmitting = true
        submitError = nil

        var payload: [String: Any] = [
            "targetType": targetType,
            "targetID": targetID,
            "reason": reason.rawValue,
        ]
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            payload["note"] = String(trimmedNote.prefix(1000))
        }

        do {
            let result = try await functions.httpsCallable("submitReport").call(payload)
            if let data = result.data as? [String: Any],
               let success = data["success"] as? Bool, success {
                await MainActor.run {
                    showSuccessToast = true
                }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                await MainActor.run { onDismiss() }
            } else {
                let message = (result.data as? [String: Any])?["message"] as? String ?? "Couldn't submit report. Try again."
                await MainActor.run { submitError = message }
            }
        } catch {
            await MainActor.run {
                submitError = error.localizedDescription
            }
        }

        await MainActor.run { isSubmitting = false }
    }
}
