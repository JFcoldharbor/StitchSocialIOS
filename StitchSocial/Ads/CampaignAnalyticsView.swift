//
//  CampaignAnalyticsView.swift
//  StitchSocial
//
//  Drill-down analytics for a single ad campaign — owner-only.
//  Reads the `campaign_stats/{campaignID}` doc maintained server-side by:
//    - onAdCampaignCreated  (initial matchedCount + averageMatchScore)
//    - rematchAdCampaign     (additional matches when brand re-runs)
//    - onAdOpportunityStatusChange (viewed / accepted / declined / expired)
//    - onAdPartnershipWrite (activePartnerships)
//    - onAdPlacementCreated (totalImpressions / totalSpend, per-creator rollup)
//
//  All the heavy lifting (auth, derived metrics, per-creator query) happens
//  in the `getCampaignAnalytics` Cloud Function. iOS just renders.
//

import SwiftUI
import FirebaseFunctions

// MARK: - Models

struct CampaignAnalytics: Decodable {
    let success: Bool
    let campaign: CampaignAnalyticsSummary
    let stats: CampaignAnalyticsStats
    let topCreators: [CampaignCreatorBreakdown]
}

struct CampaignAnalyticsSummary: Decodable {
    let id: String
    let title: String?
    let status: String?
    let budgetMin: Double?
    let budgetMax: Double?
    let cpmRate: Double?
}

struct CampaignAnalyticsStats: Decodable {
    let matchedCount: Int
    let viewedCount: Int
    let acceptedCount: Int
    let declinedCount: Int
    let expiredCount: Int
    let activePartnerships: Int
    let totalImpressions: Int
    let totalSpend: Double
    let averageMatchScore: Int
    let cpmAchieved: Double
    let acceptanceRate: Double
}

struct CampaignCreatorBreakdown: Decodable, Identifiable {
    let creatorID: String
    let impressions: Int?
    let earnings: Double?

    var id: String { creatorID }
}

// MARK: - Service Extension

extension AdService {
    /// Fetches the full analytics package for one campaign from the
    /// `getCampaignAnalytics` Cloud Function. Auth-gated server-side to the
    /// campaign owner — callers don't need to check ownership client-side.
    @MainActor
    func fetchCampaignAnalytics(campaignID: String) async throws -> CampaignAnalytics {
        let functions = Functions.functions()
        let result = try await functions.httpsCallable("getCampaignAnalytics").call([
            "campaignID": campaignID
        ])

        guard let raw = result.data as? [String: Any] else {
            throw NSError(domain: "AdService", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Empty analytics response"
            ])
        }

        let data = try JSONSerialization.data(withJSONObject: raw)
        let decoder = JSONDecoder()
        return try decoder.decode(CampaignAnalytics.self, from: data)
    }
}

// MARK: - View

struct CampaignAnalyticsView: View {
    let campaign: AdCampaign
    let onDismiss: () -> Void

    @State private var analytics: CampaignAnalytics?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let adService = AdService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                } else if let error = errorMessage {
                    errorView(error)
                } else if let a = analytics {
                    content(a)
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.cyan)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await reload() }
    }

    // MARK: - States

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load analytics")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.footnote)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Try again") {
                Task { await reload() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(20)
        }
    }

    private func content(_ a: CampaignAnalytics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                campaignHeader(a)
                fundingRow(a)
                funnelSection(a.stats)
                performanceSection(a.stats)
                if !a.topCreators.isEmpty {
                    topCreatorsSection(a.topCreators)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Sections

    private func campaignHeader(_ a: CampaignAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(a.campaign.title ?? campaign.title)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            HStack(spacing: 8) {
                Text(a.campaign.status?.capitalized ?? campaign.status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .foregroundColor(.cyan)
                Text("Avg match: \(a.stats.averageMatchScore)%")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    private func fundingRow(_ a: CampaignAnalytics) -> some View {
        HStack(spacing: 12) {
            metricCard(
                label: "Budget",
                value: budgetRange(a.campaign),
                color: .yellow,
                icon: "dollarsign.circle.fill"
            )
            metricCard(
                label: "Spent",
                value: "$\(formatMoney(a.stats.totalSpend))",
                color: .green,
                icon: "creditcard.fill"
            )
            metricCard(
                label: "CPM",
                value: a.stats.cpmAchieved > 0
                    ? "$\(String(format: "%.2f", a.stats.cpmAchieved))"
                    : "—",
                color: .cyan,
                icon: "chart.line.uptrend.xyaxis"
            )
        }
    }

    private func funnelSection(_ s: CampaignAnalyticsStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match funnel")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 6) {
                funnelRow(label: "Matched", count: s.matchedCount, ofTotal: s.matchedCount, color: .blue)
                funnelRow(label: "Viewed", count: s.viewedCount, ofTotal: s.matchedCount, color: .purple)
                funnelRow(label: "Accepted", count: s.acceptedCount, ofTotal: s.matchedCount, color: .green)
                funnelRow(label: "Declined", count: s.declinedCount, ofTotal: s.matchedCount, color: .red.opacity(0.7))
                funnelRow(label: "Expired", count: s.expiredCount, ofTotal: s.matchedCount, color: .gray)
            }

            if s.matchedCount > 0 {
                Text("Acceptance rate: \(String(format: "%.0f", s.acceptanceRate * 100))%")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
    }

    private func performanceSection(_ s: CampaignAnalyticsStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance")
                .font(.headline)
                .foregroundColor(.white)
            HStack(spacing: 12) {
                metricCard(
                    label: "Impressions",
                    value: formatCount(s.totalImpressions),
                    color: .white,
                    icon: "eye.fill"
                )
                metricCard(
                    label: "Active partners",
                    value: "\(s.activePartnerships)",
                    color: .orange,
                    icon: "person.2.fill"
                )
            }
        }
    }

    private func topCreatorsSection(_ creators: [CampaignCreatorBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top creators by impressions")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 0) {
                ForEach(Array(creators.prefix(20).enumerated()), id: \.element.id) { index, c in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 22, alignment: .leading)
                        Text(c.creatorID)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(formatCount(c.impressions ?? 0))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    if index < creators.count - 1 {
                        Divider().background(Color.white.opacity(0.05))
                    }
                }
            }
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }

    // MARK: - Helpers

    private func metricCard(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(color)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }

    private func funnelRow(label: String, count: Int, ofTotal total: Int, color: Color) -> some View {
        let pct = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                }
            }
            .frame(height: 6)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func budgetRange(_ summary: CampaignAnalyticsSummary) -> String {
        let lo = summary.budgetMin ?? campaign.budgetMin
        let hi = summary.budgetMax ?? campaign.budgetMax
        return "$\(formatMoney(lo))–$\(formatMoney(hi))"
    }

    private func formatMoney(_ v: Double) -> String {
        if v >= 1000 {
            return String(format: "%.1fK", v / 1000)
        }
        return String(format: "%.0f", v)
    }

    private func formatCount(_ v: Int) -> String {
        if v >= 1_000_000 {
            return String(format: "%.1fM", Double(v) / 1_000_000)
        } else if v >= 1000 {
            return String(format: "%.1fK", Double(v) / 1000)
        }
        return "\(v)"
    }

    // MARK: - Load

    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let a = try await adService.fetchCampaignAnalytics(campaignID: campaign.id)
            self.analytics = a
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
