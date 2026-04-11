//
//  ShowSchedule.swift
//  StitchSocial
//
//  Layer 1/4: Foundation + Service — Release cadence model and slot computation
//  Dependencies: Foundation, FirebaseFirestore
//
//  CACHING: nextAvailableSlot reads already-scheduled episodes from the caller's
//           in-memory episodesBySeasonId — zero extra Firestore reads.
//

import Foundation
import FirebaseFirestore

// MARK: - Release Cadence

enum ReleaseCadence: String, CaseIterable, Codable {
    case oneOff     = "oneOff"      // Single premiere date — not a repeating series
    case daily      = "daily"
    case weekly     = "weekly"
    case biweekly   = "biweekly"
    case monthly    = "monthly"
    case custom     = "custom"      // No auto-suggest — creator picks manually

    var displayName: String {
        switch self {
        case .oneOff:   return "One-Time"
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .biweekly: return "Bi-Weekly"
        case .monthly:  return "Monthly"
        case .custom:   return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .oneOff:   return "star.circle"
        case .daily:    return "sun.max"
        case .weekly:   return "calendar"
        case .biweekly: return "calendar.badge.clock"
        case .monthly:  return "calendar.circle"
        case .custom:   return "slider.horizontal.3"
        }
    }

    /// Days between episodes (nil = no auto-spacing)
    var intervalDays: Int? {
        switch self {
        case .oneOff:   return nil
        case .daily:    return 1
        case .weekly:   return 7
        case .biweekly: return 14
        case .monthly:  return 30
        case .custom:   return nil
        }
    }

    var isRepeating: Bool { intervalDays != nil }

    static func from(_ raw: String?) -> ReleaseCadence {
        ReleaseCadence(rawValue: raw ?? "") ?? .custom
    }
}

// MARK: - Show Schedule Config

/// Stored on the Show doc — defines the release template
struct ShowScheduleConfig: Codable, Equatable {
    var cadence: ReleaseCadence
    /// Weekday for weekly/biweekly (1=Sun, 2=Mon … 7=Sat, matching Calendar.Component.weekday)
    var releaseWeekday: Int         // default 3 = Tuesday
    /// Hour of day in 24h (0–23)
    var releaseHour: Int            // default 20 = 8pm
    /// Minute (0–59)
    var releaseMinute: Int          // default 0

    static let `default` = ShowScheduleConfig(
        cadence: .weekly,
        releaseWeekday: 3,  // Tuesday
        releaseHour: 20,
        releaseMinute: 0
    )

    var releaseTimeDisplay: String {
        var comps = DateComponents()
        comps.hour = releaseHour
        comps.minute = releaseMinute
        let date = Calendar.current.date(from: comps) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    var weekdayName: String {
        let f = DateFormatter()
        // weekday symbols are 0-indexed Sun=0; Calendar weekday is 1=Sun
        let names = f.weekdaySymbols ?? ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        let idx = max(0, min(releaseWeekday - 1, 6))
        return names[idx]
    }

    // MARK: Firestore encode/decode

    func toFirestore() -> [String: Any] {
        ["releaseCadence":   cadence.rawValue,
         "releaseWeekday":   releaseWeekday,
         "releaseHour":      releaseHour,
         "releaseMinute":    releaseMinute]
    }

    static func from(_ data: [String: Any]) -> ShowScheduleConfig? {
        guard let cadRaw = data["releaseCadence"] as? String else { return nil }
        return ShowScheduleConfig(
            cadence:       ReleaseCadence.from(cadRaw),
            releaseWeekday: data["releaseWeekday"] as? Int ?? 3,
            releaseHour:    data["releaseHour"]    as? Int ?? 20,
            releaseMinute:  data["releaseMinute"]  as? Int ?? 0
        )
    }
}

// MARK: - Schedule Service

/// Pure logic — no Firestore reads. All inputs come from the caller's already-loaded data.
/// CACHING: Zero cost — operates on in-memory episode arrays.
enum ScheduleService {

    /// Returns the next open premiere slot for a show given its cadence config
    /// and the set of already-scheduled episodes.
    ///
    /// - Parameters:
    ///   - config: The show's release cadence config
    ///   - scheduledEpisodes: Episodes with a future publishedAt (status == "scheduled")
    ///   - after: Earliest acceptable date (defaults to now + 30 min)
    /// - Returns: Suggested premiere Date, or nil if cadence is .custom
    static func nextAvailableSlot(
        config: ShowScheduleConfig,
        scheduledEpisodes: [VideoCollection],
        after minDate: Date = Date().addingTimeInterval(30 * 60)
    ) -> Date? {
        guard config.cadence != .custom else { return nil }
        guard let interval = config.cadence.intervalDays else { return nil }

        let calendar = Calendar.current
        let takenDates = scheduledEpisodes
            .compactMap { $0.publishedAt }
            .filter { $0 > minDate }

        // Find latest scheduled date — next slot starts from there
        let anchor = (takenDates.max() ?? minDate)

        // Compute candidate slots starting from anchor + 1 interval, max 52 tries
        for week in 1...52 {
            var candidate: Date

            if config.cadence == .weekly || config.cadence == .biweekly {
                // Align to the correct weekday
                let base = calendar.date(byAdding: .day,
                                          value: interval * week,
                                          to: anchor) ?? anchor
                candidate = nextOccurrence(of: config.releaseWeekday,
                                           hour: config.releaseHour,
                                           minute: config.releaseMinute,
                                           onOrAfter: base) ?? base
            } else {
                // Daily / Monthly — just add intervals
                candidate = calendar.date(byAdding: .day,
                                           value: interval * week,
                                           to: anchor) ?? anchor
                // Set release time
                candidate = calendar.date(bySettingHour: config.releaseHour,
                                           minute: config.releaseMinute,
                                           second: 0,
                                           of: candidate) ?? candidate
            }

            // Skip if too early
            guard candidate > minDate else { continue }

            // Skip if a scheduled episode is within ±12 hours of this slot
            let conflict = takenDates.contains { abs($0.timeIntervalSince(candidate)) < 43200 }
            if !conflict { return candidate }
        }

        return nil
    }

    /// Recomputes publishedAt for all episodes after a drag-reorder.
    /// Preserves cadence spacing starting from the first episode's current publishedAt.
    ///
    /// - Parameters:
    ///   - episodes: Episodes in new display order
    ///   - config: Show cadence config
    /// - Returns: Array of (episodeID, newPublishedAt) pairs — callers batch-write
    static func recomputeDates(
        for episodes: [VideoCollection],
        config: ShowScheduleConfig
    ) -> [(id: String, date: Date)] {
        guard config.cadence != .custom,
              let interval = config.cadence.intervalDays else { return [] }

        let calendar = Calendar.current
        // Anchor on first episode's publishedAt, or now if not set
        let firstDate = episodes.first?.publishedAt ?? Date().addingTimeInterval(86400)

        return episodes.enumerated().map { idx, ep in
            var date = calendar.date(byAdding: .day, value: interval * idx, to: firstDate) ?? firstDate
            date = calendar.date(bySettingHour: config.releaseHour,
                                  minute: config.releaseMinute,
                                  second: 0,
                                  of: date) ?? date
            return (ep.id, date)
        }
    }

    // MARK: - Private

    private static func nextOccurrence(of weekday: Int, hour: Int, minute: Int, onOrAfter date: Date) -> Date? {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: date)
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        var candidate = calendar.nextDate(after: date,
                                           matching: comps,
                                           matchingPolicy: .nextTimePreservingSmallerComponents)
        // Ensure it's actually on or after the input date
        if let c = candidate, c < date {
            candidate = calendar.date(byAdding: .weekOfYear, value: 1, to: c)
        }
        return candidate
    }
}
