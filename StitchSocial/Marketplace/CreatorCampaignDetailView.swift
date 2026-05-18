//
//  CreatorCampaignDetailView.swift
//  StitchSocial
//
//  Role-aware drill-down for a single Mode B campaign.
//
//  Creator view:
//    - Brief + payout + criteria
//    - "Apply" sheet (if no application yet) → calls applyToCreatorCampaign
//    - Status badge once applied (pending / approved / rejected)
//    - "Submit deliverable" sheet (if approved) → calls submitCreatorCampaignDeliverable
//    - Deliverable status block (approval / revision_requested / paid)
//
//  Brand view:
//    - Brief + payout
//    - Applicant list with AI fit score, pitch, approve/reject buttons
//    - Deliverables list with approve/revise buttons
//

import SwiftUI

struct CreatorCampaignDetailView: View {
    let campaign: CreatorCampaign
    let currentUserID: String
    let isBrandAccount: Bool
    let onDismiss: () -> Void

    @StateObject private var service = CreatorCampaignService.shared

    // Creator-side state
    @State private var myApplication: CreatorCampaignApplication?
    @State private var myDeliverable: CreatorCampaignDeliverable?

    // Brand-side state
    @State private var applications: [CreatorCampaignApplication] = []
    @State private var deliverables: [CreatorCampaignDeliverable] = []

    @State private var isLoading = true
    @State private var showingApplySheet = false
    @State private var showingSubmitSheet = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(.white)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        briefCard
                        criteriaCard
                        if isBrandAccount {
                            brandSections
                        } else {
                            creatorSections
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle(campaign.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await reload() }
        .sheet(isPresented: $showingApplySheet) {
            ApplyPitchSheet(campaign: campaign, onSubmitted: {
                showingApplySheet = false
                Task { await reload() }
            }, onDismiss: { showingApplySheet = false })
        }
        .sheet(isPresented: $showingSubmitSheet) {
            SubmitDeliverableSheet(campaignID: campaign.id, onSubmitted: {
                showingSubmitSheet = false
                Task { await reload() }
            }, onDismiss: { showingSubmitSheet = false })
        }
    }

    // MARK: - Cards (shared)

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                if let logo = campaign.brandLogoURL, let url = URL(string: logo) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Color.white.opacity(0.1) }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(campaign.brandName ?? "Brand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let cat = campaign.category {
                        Text(cat.capitalized)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Payout")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("$\(Int(campaign.payoutDollars))")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.green)
                }
            }

            Text(campaign.brief)
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .padding(.top, 4)

            if let due = campaign.contentDueDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Content due ") + Text(due, style: .date)
                }
                .font(.caption)
                .foregroundColor(.orange)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var criteriaCard: some View {
        if let c = campaign.criteria {
            VStack(alignment: .leading, spacing: 8) {
                Text("Requirements")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let t = c.minTier {
                    bullet("Minimum tier: \(t.capitalized)")
                }
                if let s = c.minStitchers, s > 0 {
                    bullet("Minimum stitchers: \(s.formatted())")
                }
                if let v = c.minViewsPerVideo, v > 0 {
                    bullet("Avg views per video: \(v.formatted())+")
                }
                if let tags = c.requiredHashtags, !tags.isEmpty {
                    bullet("Required hashtags: " + tags.map { "#\($0)" }.joined(separator: ", "))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
        .font(.footnote)
        .foregroundColor(.white.opacity(0.8))
    }

    // MARK: - Creator side

    @ViewBuilder
    private var creatorSections: some View {
        if let app = myApplication {
            applicationStatusCard(app)
            if app.status == "approved" {
                deliverableSection
            }
        } else {
            applyButton
        }
    }

    private var applyButton: some View {
        Button {
            showingApplySheet = true
        } label: {
            Text("Apply for this campaign")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(12)
        }
    }

    private func applicationStatusCard(_ app: CreatorCampaignApplication) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your application")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                statusBadge(app.status)
            }
            if let pitch = app.pitch, !pitch.isEmpty {
                Text(pitch)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
            }
            if let fit = app.aiFitScore {
                Text("AI fit: \(fit)%")
                    .font(.caption)
                    .foregroundColor(.cyan)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var deliverableSection: some View {
        if let d = myDeliverable, d.draftSubmittedAt != nil {
            deliverableStatusCard(d)
        } else {
            Button {
                showingSubmitSheet = true
            } label: {
                Text("Submit deliverable")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
    }

    private func deliverableStatusCard(_ d: CreatorCampaignDeliverable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Deliverable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                statusBadge(d.approvalStatus)
            }
            if let url = d.draftURL {
                Text(url)
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            if d.approvalStatus == "revision_requested", let notes = d.revisionNotes {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Revision notes:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                Button("Submit revision") { showingSubmitSheet = true }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(6)
            }
            if let status = d.payoutStatus {
                payoutStatusRow(status, net: d.creatorNetCents)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private func payoutStatusRow(_ status: String, net: Int?) -> some View {
        let (label, color, icon): (String, Color, String) = {
            switch status {
            case "paid", "paid_confirmed":
                return ("Paid", .green, "checkmark.circle.fill")
            case "held_no_connect_account":
                return ("Held — set up payouts", .orange, "tray.fill")
            case "failed":
                return ("Failed", .red, "exclamationmark.circle.fill")
            case "pending_stripe":
                return ("Processing", .yellow, "hourglass")
            default:
                return (status, .gray, "circle")
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
            if let n = net, status.starts(with: "paid") {
                Text("• $\(String(format: "%.2f", Double(n)/100))")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(color)
    }

    // MARK: - Brand side

    private var brandSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !applications.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Applicants (\(applications.count))")
                        .font(.headline)
                        .foregroundColor(.white)
                    ForEach(applications) { app in
                        ApplicantRow(app: app, campaignID: campaign.id, onReload: { Task { await reload() } })
                    }
                }
            }

            if !deliverables.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Deliverables (\(deliverables.count))")
                        .font(.headline)
                        .foregroundColor(.white)
                    ForEach(deliverables) { d in
                        DeliverableRow(deliverable: d, campaignID: campaign.id, onReload: { Task { await reload() } })
                    }
                }
            }

            if applications.isEmpty && deliverables.isEmpty {
                Text("No applications yet — creators will appear here as they apply.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: - Helpers

    private func statusBadge(_ status: String) -> some View {
        let (color, label): (Color, String) = {
            switch status {
            case "pending": return (.yellow, "Pending")
            case "approved": return (.green, "Approved")
            case "rejected": return (.red, "Rejected")
            case "withdrawn": return (.gray, "Withdrawn")
            case "awaiting": return (.yellow, "Awaiting review")
            case "revision_requested": return (.orange, "Revision requested")
            default: return (.gray, status.capitalized)
            }
        }()
        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    // MARK: - Load

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if isBrandAccount {
                async let a = service.fetchApplications(campaignID: campaign.id)
                async let d = service.fetchDeliverables(campaignID: campaign.id)
                self.applications = try await a
                self.deliverables = try await d
            } else {
                async let app = service.fetchApplicationStatus(campaignID: campaign.id, creatorID: currentUserID)
                async let deliv = service.fetchMyDeliverable(campaignID: campaign.id, creatorID: currentUserID)
                self.myApplication = try await app
                self.myDeliverable = try await deliv
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Apply sheet

private struct ApplyPitchSheet: View {
    let campaign: CreatorCampaign
    let onSubmitted: () -> Void
    let onDismiss: () -> Void

    @State private var pitch: String = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Why should they pick you?")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text("Tell the brand what you'd make. Keep it short — they're reviewing many applications.")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    TextEditor(text: $pitch)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .frame(minHeight: 140)
                        .foregroundColor(.white)
                        .overlay(alignment: .topLeading) {
                            if pitch.isEmpty {
                                Text("e.g., I'd build a 3-stitch reaction thread reviewing the product honestly with my usual deadpan style. My fitness audience loves unfiltered first-takes.")
                                    .font(.footnote)
                                    .foregroundColor(.gray.opacity(0.6))
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        }

                    if let err = error {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().progressViewStyle(.circular).tint(.black)
                            }
                            Text(isSubmitting ? "Sending…" : "Submit application")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .disabled(isSubmitting)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }.foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await CreatorCampaignService.shared.apply(
                campaignID: campaign.id,
                pitch: pitch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSubmitted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Submit deliverable sheet

private struct SubmitDeliverableSheet: View {
    let campaignID: String
    let onSubmitted: () -> Void
    let onDismiss: () -> Void

    @State private var draftURL: String = ""
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private var canSubmit: Bool {
        URL(string: draftURL) != nil && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Submit your content")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text("Paste a link to your draft (private YouTube, Drive, Dropbox, Stitch video, etc).")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    TextField("https://…", text: $draftURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .foregroundColor(.white)
                        .cornerRadius(10)

                    Text("Notes (optional)")
                        .font(.caption).foregroundColor(.gray)
                    TextEditor(text: $notes)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .frame(minHeight: 100)
                        .foregroundColor(.white)

                    if let err = error {
                        Text(err).font(.footnote).foregroundColor(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView().progressViewStyle(.circular).tint(.black)
                            }
                            Text(isSubmitting ? "Sending…" : "Submit for review")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(canSubmit ? Color.cyan : Color.gray.opacity(0.3))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .disabled(!canSubmit)

                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Submit deliverable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }.foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await CreatorCampaignService.shared.submitDeliverable(
                campaignID: campaignID,
                draftURL: draftURL,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSubmitted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Brand-side rows

private struct ApplicantRow: View {
    let app: CreatorCampaignApplication
    let campaignID: String
    let onReload: () -> Void

    @State private var isDeciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.creatorName ?? app.creatorID)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    if let tier = app.creatorTier {
                        Text(tier.capitalized)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                if let fit = app.aiFitScore {
                    Text("\(fit)% fit")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundColor(.cyan)
                        .clipShape(Capsule())
                }
            }

            if let pitch = app.pitch, !pitch.isEmpty {
                Text(pitch)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(4)
            }

            if let snap = app.metricSnapshot {
                HStack(spacing: 12) {
                    if let s = snap.stitcherCount { metricChip("Stitchers", String(s)) }
                    if let v = snap.viewsPerVideoAvg { metricChip("Views/vid", String(v)) }
                }
            }

            if app.status == "pending" {
                HStack(spacing: 8) {
                    Button("Approve") {
                        Task { await decide(approve: true) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(8)

                    Button("Reject") {
                        Task { await decide(approve: false) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                }
                .font(.footnote.weight(.semibold))
                .disabled(isDeciding)
            } else {
                Text(app.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.gray)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    private func metricChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundColor(.gray)
            Text(value).foregroundColor(.white).fontWeight(.semibold)
        }
        .font(.caption2)
    }

    @MainActor
    private func decide(approve: Bool) async {
        isDeciding = true
        defer { isDeciding = false }
        do {
            try await CreatorCampaignService.shared.decide(
                campaignID: campaignID,
                creatorID: app.creatorID,
                approve: approve
            )
            onReload()
        } catch {
            #if DEBUG
            print("decide error: \(error)")
            #endif
        }
    }
}

private struct DeliverableRow: View {
    let deliverable: CreatorCampaignDeliverable
    let campaignID: String
    let onReload: () -> Void

    @State private var isReviewing = false
    @State private var showRevisionSheet = false
    @State private var revisionNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(deliverable.creatorID)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(deliverable.approvalStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
            }
            if let url = deliverable.draftURL, let parsed = URL(string: url) {
                Link(destination: parsed) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text(url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                }
            }

            if deliverable.approvalStatus == "awaiting" && deliverable.draftURL != nil {
                HStack(spacing: 8) {
                    Button("Approve & pay") {
                        Task { await review(approve: true) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(8)

                    Button("Request revision") {
                        showRevisionSheet = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(8)
                }
                .font(.footnote.weight(.semibold))
                .disabled(isReviewing)
            }

            if let status = deliverable.payoutStatus {
                Text("Payout: \(status.replacingOccurrences(of: "_", with: " "))")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .sheet(isPresented: $showRevisionSheet) {
            revisionSheet
        }
    }

    private var revisionSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tell the creator what to change")
                        .font(.headline)
                        .foregroundColor(.white)
                    TextEditor(text: $revisionNotes)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .frame(minHeight: 140)
                        .foregroundColor(.white)
                    Button("Send revision request") {
                        Task {
                            await review(approve: false, notes: revisionNotes)
                            showRevisionSheet = false
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .font(.headline)
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Request revision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showRevisionSheet = false }.foregroundColor(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @MainActor
    private func review(approve: Bool, notes: String = "") async {
        isReviewing = true
        defer { isReviewing = false }
        do {
            _ = try await CreatorCampaignService.shared.reviewDeliverable(
                campaignID: campaignID,
                creatorID: deliverable.creatorID,
                approve: approve,
                revisionNotes: notes
            )
            onReload()
        } catch {
            #if DEBUG
            print("review error: \(error)")
            #endif
        }
    }
}
