//
//  VideoAnalyticsSheet.swift
//  StitchSocial
//
//  Creator-facing analytics for a single video. Replaces the simple
//  WhoViewedSheet — that one only listed viewers. This one shows the metrics
//  an advertiser or sponsor would actually evaluate: impressions, completion
//  rate, daily curve, peak hour, retention buckets.
//
//  Tabs:
//    Overview  — headline numbers + 7-day chart
//    Retention — quartile drop-off + peak hour
//    Viewers   — existing WhoViewedSheet body, kept as a sub-tab
//
//  Access control: owner-only. The presenter is responsible for gating.
//

import SwiftUI
import Charts

struct VideoAnalyticsSheet: View {

    // MARK: - Inputs

    let videoID: String
    let videoDuration: TimeInterval
    var onDismiss: (() -> Void)? = nil

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var analytics: VideoAnalyticsDetailed?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    private let tabs = ["Overview", "Retention", "Viewers"]

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView().tint(.cyan)
                Text("Loading analytics…").font(.caption).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            errorView(err)
        } else if let a = analytics {
            VStack(spacing: 0) {
                tabBar
                ScrollView {
                    Group {
                        switch selectedTab {
                        case 0: overviewTab(a)
                        case 1: retentionTab(a)
                        case 2: viewersTab
                        default: EmptyView()
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { idx in
                Button {
                    selectedTab = idx
                } label: {
                    VStack(spacing: 6) {
                        Text(tabs[idx])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedTab == idx ? .white : .gray)
                        Rectangle()
                            .fill(selectedTab == idx ? Color.cyan : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
    }

    // MARK: - Overview Tab

    private func overviewTab(_ a: VideoAnalyticsDetailed) -> some View {
        VStack(spacing: 20) {
            // Top stat grid
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                statCard("Views", value: "\(a.basic.totalViews)", icon: "eye.fill", tint: .cyan)
                statCard("Unique Viewers", value: "\(a.basic.uniqueViewers)", icon: "person.2.fill", tint: .purple)
                statCard("Avg Watch", value: formatDuration(a.basic.averageWatchTime), icon: "clock.fill", tint: .orange)
                statCard("Completion", value: percentString(a.retention.completionRate), icon: "checkmark.circle.fill", tint: .green)
                statCard("Engagement", value: percentString(a.basic.engagementRate), icon: "flame.fill", tint: .red)
                statCard("Replies", value: "\(a.replyCount)", icon: "bubble.left.fill", tint: .blue)
            }
            .padding(.horizontal)

            // 7-day view chart
            sectionHeader("Last 7 Days")
            Chart(a.dailyViews) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Views", point.count)
                )
                .foregroundStyle(Color.cyan.gradient)
                .cornerRadius(4)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel().foregroundStyle(Color.gray)
                }
            }
            .padding(.horizontal)

            // Total watch time
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Watch Time")
                    .font(.caption).foregroundColor(.gray)
                Text(formatDuration(a.basic.totalWatchTime, longForm: true))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .padding(.bottom, 30)
    }

    // MARK: - Retention Tab

    private func retentionTab(_ a: VideoAnalyticsDetailed) -> some View {
        VStack(spacing: 20) {
            sectionHeader("Where Viewers Drop Off")

            Chart(a.retention.values, id: \.label) { item in
                BarMark(
                    x: .value("Quartile", item.label),
                    y: .value("Viewers", item.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.red.opacity(0.8), Color.green.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(4)
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Color.gray)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel().foregroundStyle(Color.gray)
                }
            }
            .padding(.horizontal)

            // Per-bucket breakdown rows
            VStack(spacing: 8) {
                ForEach(a.retention.values, id: \.label) { item in
                    HStack {
                        Text(item.label)
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(item.count) viewer\(item.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)

            // Peak hour
            if let peak = a.peakHour {
                sectionHeader("Peak Activity")
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18))
                        .foregroundColor(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatHour(peak))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Most viewers engage at this hour")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Sample size footnote
            Text("Based on \(a.scannedInteractions) engaged view\(a.scannedInteractions == 1 ? "" : "s") (≥ 5s watch time)")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.horizontal)
        }
        .padding(.bottom, 30)
    }

    // MARK: - Viewers Tab

    private var viewersTab: some View {
        WhoViewedSheetBody(videoID: videoID)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal)
    }

    private func statCard(_ title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }

    private func formatDuration(_ seconds: TimeInterval, longForm: Bool = false) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if longForm {
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 { return "\(m)m \(s)s" }
            return "\(s)s"
        }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m):\(String(format: "%02d", s))" }
        return "\(s)s"
    }

    private func percentString(_ value: Double) -> String {
        let pct = Int((value * 100).rounded())
        return "\(pct)%"
    }

    private func formatHour(_ hour: Int) -> String {
        let cal = Calendar.current
        let comps = DateComponents(hour: hour)
        guard let date = cal.date(from: comps) else { return "\(hour):00" }
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        return fmt.string(from: date)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Couldn't load analytics")
                .foregroundColor(.white)
            Text(msg)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                errorMessage = nil
                Task { await load() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.cyan)
            .foregroundColor(.black)
            .cornerRadius(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let svc = VideoService()
            let result = try await svc.getVideoAnalyticsDetailed(
                videoID: videoID,
                duration: videoDuration
            )
            self.analytics = result
        } catch {
            #if DEBUG
            print("❌ ANALYTICS: \(error)")
            #endif
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - WhoViewedSheet Body Adapter

/// Lightweight wrapper that reuses the existing WhoViewedSheet content area.
/// If your WhoViewedSheet is already a NavigationView-based view, this
/// embeds its body. If it's a sheet root, swap in its inner content instead.
private struct WhoViewedSheetBody: View {
    let videoID: String

    var body: some View {
        WhoViewedSheet(videoID: videoID, onDismiss: {})
    }
}
