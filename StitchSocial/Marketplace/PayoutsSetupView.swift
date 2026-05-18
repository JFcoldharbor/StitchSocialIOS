//
//  PayoutsSetupView.swift
//  StitchSocial
//
//  Stripe Connect onboarding screen for creators who want to receive
//  campaign payouts. Calls createCreatorStripeOnboarding to get a Stripe-
//  hosted URL, opens it in an in-app SafariView, then re-syncs status via
//  refreshCreatorStripeStatus when the user returns.
//
//  Also surfaces held payouts (campaigns approved before account was active)
//  and offers a one-tap retry via retryHeldPayouts.
//

import SwiftUI
import SafariServices

struct PayoutsSetupView: View {
    @ObservedObject var service = CreatorCampaignService.shared

    @State private var status: CreatorCampaignService.StripeAccountStatus?
    @State private var isLoadingStatus = true
    @State private var isStartingOnboarding = false
    @State private var safariURL: URL?
    @State private var errorMessage: String?
    @State private var retryResult: (succeeded: Int, failed: Int)?
    @State private var isRetrying = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard
                    statusCard
                    if status?.status == "active" {
                        heldPayoutsCard
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Payouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadStatus() }
        .sheet(item: $safariURL) { url in
            SafariView(url: url, onDismiss: {
                safariURL = nil
                Task { await loadStatus() }
            })
            .ignoresSafeArea()
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.and.123")
                    .foregroundColor(.cyan)
                Text("Receive campaign earnings")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text("Connect a bank account through Stripe to receive payouts from approved campaign deliverables. Stripe handles KYC and tax forms — Stitch never sees your bank details.")
                .font(.footnote)
                .foregroundColor(.gray)
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 11))
                Text("Powered by Stripe")
                    .font(.caption2)
            }
            .foregroundColor(.gray.opacity(0.7))
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account status")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gray)
                Spacer()
                if isLoadingStatus {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    statusBadge
                }
            }
            primaryAction
            if let reqs = status?.requirements, !reqs.isEmpty, status?.status != "active" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Still needed by Stripe:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    ForEach(reqs, id: \.self) { req in
                        Text("• \(req)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch status?.status {
            case "active": return ("Active", .green)
            case "pending_verification": return ("Pending verification", .orange)
            case "onboarding": return ("Onboarding in progress", .yellow)
            default: return ("Not set up", .gray)
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

    @ViewBuilder
    private var primaryAction: some View {
        if status?.status == "active" {
            Label("Payouts are active — earnings will deposit automatically.", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundColor(.green)
        } else {
            Button {
                Task { await startOnboarding() }
            } label: {
                HStack {
                    if isStartingOnboarding {
                        ProgressView().progressViewStyle(.circular).tint(.black)
                    }
                    Text(status == nil || status?.status == "none"
                         ? "Set up payouts"
                         : "Continue setup")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(10)
            }
            .disabled(isStartingOnboarding)
        }
    }

    private var heldPayoutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tray.full.fill")
                    .foregroundColor(.cyan)
                Text("Sweep held payouts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
            Text("If any campaigns approved before you connected payouts, sweep them now to release the funds.")
                .font(.footnote)
                .foregroundColor(.gray)
            Button {
                Task { await retry() }
            } label: {
                HStack {
                    if isRetrying { ProgressView().progressViewStyle(.circular).tint(.white) }
                    Text(isRetrying ? "Sweeping…" : "Sweep now")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.2))
                .foregroundColor(.cyan)
                .cornerRadius(8)
            }
            .disabled(isRetrying)
            if let r = retryResult {
                Text("Released: \(r.succeeded). Still failing: \(r.failed).")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Actions

    @MainActor
    private func loadStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        do {
            self.status = try await service.refreshStripeStatus()
        } catch {
            self.errorMessage = "Couldn't load status: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startOnboarding() async {
        isStartingOnboarding = true
        defer { isStartingOnboarding = false }
        do {
            let r = try await service.createStripeOnboarding()
            safariURL = r.onboardingURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func retry() async {
        isRetrying = true
        defer { isRetrying = false }
        do {
            retryResult = try await service.retryHeldPayouts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SafariView wrapper

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }
