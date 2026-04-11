//
//  PremiereDatePicker.swift
//  StitchSocial
//
//  Layer 6: Views — Standalone premiere scheduling control
//  Drop-in anywhere a creator chooses when to publish content.
//  Zero Firestore dependency — callers own the write.
//
//  Usage:
//    PremiereDatePicker(intent: $publishIntent)
//
//  Then in your save/finalize:
//    switch publishIntent {
//    case .draft:            status = "draft"
//    case .publishNow:       status = "published"; publishedAt = serverTimestamp()
//    case .scheduled(let d): status = "scheduled"; publishedAt = Timestamp(date: d)
//    }
//

import SwiftUI
import FirebaseFirestore

// MARK: - Publish Intent

/// What the creator wants to do with their content.
/// Callers map this to Firestore fields — no coupling to any specific model.
enum PublishIntent: Equatable {
    case draft
    case publishNow
    case scheduled(Date)

    var statusString: String {
        switch self {
        case .draft:        return "draft"
        case .publishNow:   return "published"
        case .scheduled:    return "scheduled"
        }
    }

    /// The publishedAt value to write. Nil = use serverTimestamp() on caller side.
    var publishedAt: Date? {
        switch self {
        case .scheduled(let d): return d
        default:                return nil
        }
    }

    var isScheduled: Bool {
        if case .scheduled = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .draft:              return "Draft"
        case .publishNow:         return "Publish Now"
        case .scheduled(let d):   return "Premieres \(Self.shortFormat(d))"
        }
    }

    private static func shortFormat(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" :
                       Calendar.current.isDateInTomorrow(date) ? "'Tomorrow' h:mm a" : "MMM d 'at' h:mm a"
        return f.string(from: date)
    }

    /// Convert from stored Firestore status + publishedAt back to intent
    static func from(status: String, publishedAt: Date?) -> PublishIntent {
        switch status {
        case "published": return .publishNow
        case "scheduled":
            if let d = publishedAt, d > Date() { return .scheduled(d) }
            return .publishNow   // Scheduled date passed — treat as published
        default: return .draft
        }
    }
}

// MARK: - PremiereDatePicker

/// Standalone premiere scheduling control. Compact, dark-themed.
/// Bind to a `PublishIntent` — zero Firestore dependency.
struct PremiereDatePicker: View {

    @Binding var intent: PublishIntent

    /// Minimum schedulable date (defaults to 30 minutes from now)
    var minimumDate: Date = Date().addingTimeInterval(30 * 60)

    // Internal picker state — only shown when .scheduled
    @State private var pickerDate: Date
    @State private var pickerMode: Mode = .draft

    private enum Mode: Int, CaseIterable {
        case draft, publishNow, scheduled

        var label: String {
            switch self { case .draft: return "Draft"; case .publishNow: return "Publish Now"; case .scheduled: return "Premiere Date" }
        }
        var icon: String {
            switch self { case .draft: return "doc.badge.ellipsis"; case .publishNow: return "checkmark.circle"; case .scheduled: return "calendar.badge.clock" }
        }
        var accent: Color {
            switch self { case .draft: return .gray; case .publishNow: return .green; case .scheduled: return .cyan }
        }
    }

    /// Suggested date from ScheduleService.nextAvailableSlot — shown as a hint, not enforced
    var suggestedDate: Date?

    init(intent: Binding<PublishIntent>, minimumDate: Date = Date().addingTimeInterval(30 * 60), suggestedDate: Date? = nil) {
        self._intent = intent
        self.minimumDate = minimumDate
        self.suggestedDate = suggestedDate

        // Sync internal state from initial intent
        switch intent.wrappedValue {
        case .draft:
            self._pickerMode = State(initialValue: .draft)
            self._pickerDate = State(initialValue: Self.defaultScheduleDate())
        case .publishNow:
            self._pickerMode = State(initialValue: .publishNow)
            self._pickerDate = State(initialValue: Self.defaultScheduleDate())
        case .scheduled(let d):
            self._pickerMode = State(initialValue: .scheduled)
            self._pickerDate = State(initialValue: d > minimumDate ? d : Self.defaultScheduleDate())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Mode selector ──
            HStack(spacing: 6) {
                ForEach(Mode.allCases, id: \.rawValue) { mode in
                    modeChip(mode)
                }
            }

            // ── Auto-suggest chip (when cadence is set and mode is not yet scheduled) ──
            if let suggested = suggestedDate, pickerMode != .scheduled {
                Button {
                    pickerDate = suggested
                    pickerMode = .scheduled
                    syncIntent()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "wand.and.stars").font(.system(size: 10)).foregroundColor(.cyan)
                        Text("Suggested: \(Self.shortSuggestionLabel(suggested))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // ── Date/time picker (scheduled only) ──
            if pickerMode == .scheduled {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker(
                        "Premiere at",
                        selection: $pickerDate,
                        in: minimumDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .tint(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .onChange(of: pickerDate) { _, newDate in
                        intent = .scheduled(newDate)
                    }

                    // Human-readable confirmation
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 11))
                            .foregroundColor(.cyan)
                        Text("Will premiere \(relativeLabel(for: pickerDate))")
                            .font(.system(size: 11))
                            .foregroundColor(.cyan.opacity(0.85))
                    }
                    .padding(.horizontal, 4)
                }
            }

            // ── Status summary badge ──
            HStack(spacing: 5) {
                Circle()
                    .fill(pickerMode.accent)
                    .frame(width: 6, height: 6)
                Text(intent.label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Mode Chip

    private func modeChip(_ mode: Mode) -> some View {
        let selected = pickerMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                pickerMode = mode
                syncIntent()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10))
                Text(mode.label)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .foregroundColor(selected ? .black : .white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? mode.accent : Color.white.opacity(0.08))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func syncIntent() {
        switch pickerMode {
        case .draft:       intent = .draft
        case .publishNow:  intent = .publishNow
        case .scheduled:   intent = .scheduled(pickerDate)
        }
    }

    private func relativeLabel(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let rel = f.localizedString(for: date, relativeTo: Date())
        let abs = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        return "\(rel) (\(abs))"
    }

    private static func shortSuggestionLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInTomorrow(date) ? "'Tomorrow' h:mm a" : "EEE MMM d 'at' h:mm a"
        return f.string(from: date)
    }

    private static func defaultScheduleDate() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow)!
    }
}

// MARK: - Firestore Write Helper

extension PublishIntent {
    /// Applies this intent's fields to a Firestore data dict.
    /// Callers merge this into their existing write payload.
    func firestoreFields() -> [String: Any] {
        var fields: [String: Any] = ["status": statusString]
        switch self {
        case .publishNow:
            fields["publishedAt"] = FieldValue.serverTimestamp()
        case .scheduled(let d):
            fields["publishedAt"] = Timestamp(date: d)
        case .draft:
            break   // No publishedAt change on draft save
        }
        return fields
    }
}

// MARK: - Preview

#if DEBUG
struct PremiereDatePicker_Previews: PreviewProvider {
    @State static var intent: PublishIntent = .draft
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                PremiereDatePicker(intent: $intent)
                Text(intent.label).foregroundColor(.white)
            }
            .padding(20)
        }
    }
}
#endif
