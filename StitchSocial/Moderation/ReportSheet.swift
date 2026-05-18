//
//  ReportSheet.swift
//  StitchSocial
//
//  Bottom sheet for reporting a video or user. Two-step flow:
//    1. Pick a category (ReportReason)
//    2. Optional details + Submit
//
//  Usage:
//      @State private var showingReport = false
//      Button("Report") { showingReport = true }
//      .sheet(isPresented: $showingReport) {
//          ReportSheet(targetType: .video, targetID: video.id, offendingUserID: video.creatorID)
//      }
//

import SwiftUI

struct ReportSheet: View {

    // MARK: - Inputs

    let targetType: ReportTargetType
    let targetID: String
    let offendingUserID: String

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = ReportService.shared

    @State private var selectedReason: ReportReason?
    @State private var details: String = ""
    @State private var didSubmit = false
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if didSubmit {
                    thankYouView
                } else if selectedReason == nil {
                    categoryList
                } else {
                    detailsForm
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(didSubmit ? "Done" : "Cancel") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
            .alert("Couldn't submit", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Category List

    private var categoryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's wrong with this \(targetType == .video ? "video" : "account")?")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("Reports are confidential. Reviewers see the report, not your identity.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                ForEach(ReportReason.allCases) { reason in
                    Button {
                        selectedReason = reason
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: reason.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.cyan)
                                .frame(width: 32, height: 32)
                                .background(Color.cyan.opacity(0.15))
                                .clipShape(Circle())
                            Text(reason.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Details Form

    private var detailsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    selectedReason = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.cyan)
                }
                Spacer()
            }

            if let reason = selectedReason {
                HStack {
                    Image(systemName: reason.iconName).foregroundColor(.cyan)
                    Text(reason.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }

            Text("Add details (optional)")
                .font(.caption)
                .foregroundColor(.gray)

            ZStack(alignment: .topLeading) {
                if details.isEmpty {
                    Text("What did you see? When did it happen?")
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $details)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(4)
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(10)

            Button(action: submit) {
                HStack {
                    if service.isSubmitting {
                        ProgressView().tint(.black)
                    }
                    Text(service.isSubmitting ? "Submitting…" : "Submit Report")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.cyan)
                .cornerRadius(12)
            }
            .disabled(service.isSubmitting)

            Spacer()
        }
        .padding()
    }

    // MARK: - Thank You

    private var thankYouView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("Report submitted")
                .font(.title3.bold())
                .foregroundColor(.white)
            Text("Our team will review it. Thank you for helping keep Stitch safe.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func submit() {
        guard let reason = selectedReason else { return }
        Task {
            do {
                try await service.submitReport(
                    targetType: targetType,
                    targetID: targetID,
                    offendingUserID: offendingUserID,
                    reason: reason,
                    details: details.isEmpty ? nil : details
                )
                didSubmit = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
