//
//  VideoAnalyticsDetailed.swift
//  StitchSocial
//
//  Creator analytics — the "ads would want to see" view. Wraps the existing
//  VideoAnalytics with time-series + retention buckets + peak-hour signal so
//  the analytics sheet can show daily views, when viewers drop off, and when
//  the audience is most active.
//
//  Server-side aggregation is overkill at current scale — we aggregate
//  client-side from the `interactions` collection per video. Re-evaluate if
//  any single video crosses ~5k interactions.
//

import Foundation
import FirebaseFirestore

// MARK: - Models

/// Daily view bucket for the line/bar chart.
struct DailyViewPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let count: Int
}

/// Watch-retention buckets. Each value is the number of viewers whose
/// final watchTime fell into that quartile of the video's duration.
struct RetentionBuckets: Equatable {
    let quarter1: Int  // 0–25%   — bounced
    let quarter2: Int  // 25–50%  — partial
    let quarter3: Int  // 50–75%  — engaged
    let quarter4: Int  // 75–100% — completed

    /// Share of viewers who watched at least 75% of the video.
    var completionRate: Double {
        let total = quarter1 + quarter2 + quarter3 + quarter4
        return total > 0 ? Double(quarter4) / Double(total) : 0
    }

    var values: [(label: String, count: Int)] {
        [("0–25%", quarter1), ("25–50%", quarter2), ("50–75%", quarter3), ("75–100%", quarter4)]
    }
}

/// Full creator analytics for a single video. Combines the in-doc counters
/// (views, hypes, etc.) with derived series from the interactions collection.
struct VideoAnalyticsDetailed {
    let basic: VideoAnalytics
    let replyCount: Int
    let dailyViews: [DailyViewPoint]      // last 7 days, oldest → newest
    let retention: RetentionBuckets
    let peakHour: Int?                    // 0–23, hour with most interactions across all time
    let scannedInteractions: Int          // sample size powering this aggregation
}

// MARK: - Service Extension

extension VideoService {

    /// Detailed analytics for a single video. Pass `duration` so we can bucket
    /// retention; if duration is 0 the retention buckets will be all-zero.
    ///
    /// Cost: one Firestore range query against `interactions` filtered by
    /// videoID + a single video doc read (inside `getVideoAnalytics`). For a
    /// video with 1k views that's ~$0.0006 per call — fine for owner-only
    /// access; cache if you ever surface this elsewhere.
    func getVideoAnalyticsDetailed(
        videoID: String,
        duration: TimeInterval
    ) async throws -> VideoAnalyticsDetailed {

        // Reuse existing aggregation for the headline numbers.
        let basic = try await getVideoAnalytics(videoID: videoID)

        // Fetch all interactions for this video. They're already filtered to
        // engaged views (watchTime >= 5s) by trackVideoView's gate.
        let snapshot = try await Firestore.firestore(database: "stitchfin")
            .collection(FirebaseSchema.Collections.interactions)
            .whereField(FirebaseSchema.InteractionDocument.videoID, isEqualTo: videoID)
            .getDocuments()

        // Build the 7-day bucket scaffold so days with zero views still appear
        // in the chart (avoids gappy timeline visuals).
        let calendar = Calendar.current
        let now = Date()
        let oldestDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        var dailyMap: [Date: Int] = [:]
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: oldestDay) {
                dailyMap[calendar.startOfDay(for: day)] = 0
            }
        }

        var q1 = 0, q2 = 0, q3 = 0, q4 = 0
        var hourCounts = Array(repeating: 0, count: 24)

        for doc in snapshot.documents {
            let data = doc.data()
            guard let ts = (data["createdAt"] as? Timestamp)?.dateValue() else { continue }
            let watch = (data["watchTime"] as? TimeInterval) ?? 0

            // Daily bucket — only counts interactions in the last 7 days
            let day = calendar.startOfDay(for: ts)
            if day >= oldestDay {
                dailyMap[day, default: 0] += 1
            }

            // Hour-of-day bucket (across all time, for peak signal)
            let hour = calendar.component(.hour, from: ts)
            hourCounts[hour] += 1

            // Retention bucket
            if duration > 0 {
                let pct = watch / duration
                switch pct {
                case ..<0.25:  q1 += 1
                case ..<0.5:   q2 += 1
                case ..<0.75:  q3 += 1
                default:       q4 += 1
                }
            }
        }

        let dailyViews = dailyMap
            .sorted { $0.key < $1.key }
            .map { DailyViewPoint(date: $0.key, count: $0.value) }

        // Find the hour with the most interactions. nil if no interactions.
        let peakHour: Int? = {
            let totalInteractions = hourCounts.reduce(0, +)
            guard totalInteractions > 0 else { return nil }
            return hourCounts.enumerated().max(by: { $0.element < $1.element })?.offset
        }()

        // replyCount lives on the video doc itself (denormalized counter).
        let videoDoc = try await Firestore.firestore(database: "stitchfin")
            .collection(FirebaseSchema.Collections.videos)
            .document(videoID)
            .getDocument()
        let replyCount = videoDoc.data()?[FirebaseSchema.VideoDocument.replyCount] as? Int ?? 0

        return VideoAnalyticsDetailed(
            basic: basic,
            replyCount: replyCount,
            dailyViews: dailyViews,
            retention: RetentionBuckets(quarter1: q1, quarter2: q2, quarter3: q3, quarter4: q4),
            peakHour: peakHour,
            scannedInteractions: snapshot.documents.count
        )
    }
}
