//
//  CreateCreatorCampaignView.swift
//  StitchSocial
//
//  Brand-facing form to post a Mode B (marketplace) campaign.
//  On submit → writes creatorCampaigns/{id} which triggers
//  onCreatorCampaignCreated server-side (embed + match + notify).
//

import SwiftUI

struct CreateCreatorCampaignView: View {
    let brandID: String
    let brandName: String
    let brandLogoURL: String?
    let onCreated: (String) -> Void
    let onDismiss: () -> Void

    // Required
    @State private var title: String = ""
    @State private var brief: String = ""
    @State private var payoutDollars: String = "100"
    @State private var category: String = "lifestyle"

    // Criteria
    @State private var minTier: String = "rising"
    @State private var minStitchers: String = "1000"
    @State private var minViewsPerVideo: String = ""
    @State private var requiredHashtagsText: String = ""

    // Deadline
    @State private var hasDueDate: Bool = false
    @State private var contentDueDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 14)

    // State
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let categories = ["lifestyle", "fitness", "beauty", "technology", "food", "music", "gaming", "fashion", "other"]
    private let tiers = ["rookie", "rising", "veteran", "influencer", "legendary", "founder"]

    private var canSubmit: Bool {
        !title.isEmpty
            && brief.count >= 20
            && (Int(payoutDollars) ?? 0) >= 5
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Campaign brief") {
                            input("Title", text: $title, placeholder: "e.g., Summer skincare reveal")
                            multiline("Brief", text: $brief, placeholder: "What should creators make? Tone, must-include points, hashtags, links. Min 20 chars.")
                            picker("Category", selection: $category, options: categories)
                        }

                        section("Payout") {
                            HStack {
                                Text("$")
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.green)
                                TextField("", text: $payoutDollars)
                                    .keyboardType(.numberPad)
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.white)
                                Text("per approved deliverable")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(10)
                            Text("Stitch takes 20% — creator nets $\(creatorNet) per approved delivery")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        section("Creator requirements") {
                            picker("Minimum tier", selection: $minTier, options: tiers)
                            input("Min stitchers (followers)", text: $minStitchers, keyboard: .numberPad, placeholder: "1000")
                            input("Min views per video", text: $minViewsPerVideo, keyboard: .numberPad, placeholder: "Optional")
                            input("Required hashtags (comma-separated)", text: $requiredHashtagsText, placeholder: "fitness, workout")
                        }

                        section("Timeline") {
                            Toggle(isOn: $hasDueDate) {
                                Text("Set content due date")
                                    .font(.footnote)
                                    .foregroundColor(.white)
                            }
                            .tint(.cyan)
                            if hasDueDate {
                                DatePicker(
                                    "Due",
                                    selection: $contentDueDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .colorScheme(.dark)
                                .foregroundColor(.white)
                            }
                        }

                        if let err = errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                if isSubmitting {
                                    ProgressView().progressViewStyle(.circular).tint(.black)
                                }
                                Text(isSubmitting ? "Posting…" : "Post campaign")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? Color.white : Color.gray.opacity(0.3))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        .disabled(!canSubmit)

                        Text("By posting, you agree to fund payouts in full upon approval. Creators receive earnings via Stripe Connect.")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("New campaign")
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
        }
    }

    private var creatorNet: String {
        let p = Double(payoutDollars) ?? 0
        return String(format: "%.2f", p * 0.8)
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundColor(.gray)
            content()
        }
    }

    private func input(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.gray)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
        }
    }

    private func multiline(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.gray)
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .frame(minHeight: 100, maxHeight: 160)
                .foregroundColor(.white)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func picker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.gray)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { o in
                    Text(o.capitalized).tag(o)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
        }
    }

    // MARK: - Submit

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let payoutCents = Int((Double(payoutDollars) ?? 0) * 100)
        let hashtags = requiredHashtagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        let criteria = CreatorCampaignCriteria(
            minTier: minTier,
            minStitchers: Int(minStitchers),
            minViewsPerVideo: Int(minViewsPerVideo),
            requiredHashtags: hashtags.isEmpty ? nil : hashtags,
            preferredCategories: [category]
        )

        do {
            let id = try await CreatorCampaignService.shared.createCampaign(
                brandID: brandID,
                brandName: brandName,
                brandLogoURL: brandLogoURL,
                title: title,
                brief: brief,
                category: category,
                payoutCents: payoutCents,
                criteria: criteria,
                contentDueDate: hasDueDate ? contentDueDate : nil
            )
            onCreated(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
