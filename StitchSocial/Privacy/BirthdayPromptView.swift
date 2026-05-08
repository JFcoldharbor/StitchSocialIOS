//
//  BirthdayPromptView.swift
//  StitchSocial
//
//  Force-collects DOB on first profile load.  Server-side Cloud Function
//  (`onUserBirthdateSet`) is the source of truth for ageGroup; this view
//  just captures the date and writes it.  COPPA-defensive: under-13 cannot
//  proceed.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BirthdayPromptView: View {
    let userID: String
    let onCompleted: (AgeGroup) -> Void
    let onUnder13: () -> Void

    @State private var selectedDate: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let minDate = Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? Date()
    private let maxDate = Date()

    private var computedAge: Int {
        Calendar.current.dateComponents([.year], from: selectedDate, to: Date()).year ?? 0
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Header
                VStack(spacing: 10) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.cyan)
                    Text("When's your birthday?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("We use this once to set up your account and never show it on your profile.")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Date picker
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: minDate...maxDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.horizontal)

                // Computed age preview
                Text("Age: \(computedAge)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.cyan.opacity(0.8))

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                // Continue
                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.black)
                        } else {
                            Text("Continue")
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan)
                    .cornerRadius(12)
                }
                .disabled(isSaving)
                .padding(.horizontal, 24)

                Spacer()

                Text("By continuing you confirm this is your real date of birth.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Actions

    private func save() {
        let age = computedAge

        // Sanity: pickers can't go forward but check anyway
        guard age >= 0 else { return }

        // COPPA defensiveness — block under-13 outright.
        if age < 13 {
            // Mark the user doc and sign them out so they can't retry.
            isSaving = true
            Task {
                let db = Firestore.firestore(database: Config.Firebase.databaseName)
                try? await db.collection("users").document(userID).setData([
                    "privacySettings": [
                        "birthdate": Timestamp(date: selectedDate),
                        "ageGroup": "blocked",
                        "blockedAt": Timestamp(date: Date()),
                        "blockReason": "under_13_coppa"
                    ]
                ], merge: true)
                try? Auth.auth().signOut()
                await MainActor.run {
                    isSaving = false
                    onUnder13()
                }
            }
            return
        }

        let group: AgeGroup = age >= 18 ? .adult : .teen

        isSaving = true
        Task {
            do {
                let db = Firestore.firestore(database: Config.Firebase.databaseName)
                try await db.collection("users").document(userID).setData([
                    "privacySettings": [
                        "birthdate": Timestamp(date: selectedDate),
                        "ageGroup": group.rawValue,
                        "ageVerifiedAt": Timestamp(date: Date())
                    ]
                ], merge: true)

                // Force a token refresh so the server-side Cloud Function's
                // custom claim (`audienceLane`) is picked up by the next
                // Firestore request.  Function fires on doc update.
                try? await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)

                await MainActor.run {
                    isSaving = false
                    onCompleted(group)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Couldn't save: \(error.localizedDescription)"
                }
            }
        }
    }
}
