//
//  CreatorScheduleView.swift
//  StitchSocial
//
//  Layer 6: Views — Creator Master Schedule Calendar
//  Entry: AllCollectionsView calendar icon → this page
//
//  CREATOR MODE (isOwner=true):
//    - Sees all statuses (draft, scheduled, published)
//    - Tap episode → opens EpisodeEditorView to reschedule
//    - Empty day slot tap → intent to create episode for that date
//
//  VIEWER MODE (isOwner=false):
//    - Only sees status=scheduled + published from last 7 days forward
//    - Bell tap → subscribe to premiere notification
//
//  DATA:
//    - Single Firestore query: videoCollections where creatorID == X
//    - Filtered + grouped client-side by publishedAt date
//    - Cached 5 min in ScheduleDataService.shared
//
//  CACHING: ScheduleDataService.shared — 5-min TTL, invalidated on episode save
//  BATCHING: One query covers all shows/episodes for the creator
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Schedule Data Service

@MainActor
class ScheduleDataService {

    static let shared = ScheduleDataService()
    private init() {}

    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private var cache: [String: (items: [ScheduleItem], fetchedAt: Date)] = [:]
    private let ttl: TimeInterval = 300

    func getSchedule(creatorID: String, isOwner: Bool) async throws -> [ScheduleItem] {
        let key = "\(creatorID):\(isOwner)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.items
        }

        // One query — all episodes for this creator
        // CACHING: 5-min TTL covers rapid tab switches
        // Requires index: creatorID ASC + publishedAt ASC (videoCollections)
        var query: Query = db.collection("videoCollections")
            .whereField("creatorID", isEqualTo: creatorID)

        if !isOwner {
            // Viewers: only scheduled/published from last 7 days forward
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            query = query
                .whereField("status", in: ["scheduled", "published"])
                .whereField("publishedAt", isGreaterThan: Timestamp(date: cutoff))
        }

        let snap = try await query.order(by: "publishedAt").getDocuments()
        let items = snap.documents.compactMap { ScheduleItem(doc: $0) }

        cache[key] = (items, Date())
        print("📅 SCHEDULE: Loaded \(items.count) items for \(creatorID) (owner: \(isOwner))")
        return items
    }

    func invalidate(creatorID: String) {
        cache.removeValue(forKey: "\(creatorID):true")
        cache.removeValue(forKey: "\(creatorID):false")
    }
}

// MARK: - Schedule Item Model

struct ScheduleItem: Identifiable {
    let id: String
    let title: String
    let episodeTitle: String
    let showId: String?
    let seasonId: String?
    let episodeNumber: Int?
    let contentType: CollectionContentType
    let status: CollectionStatus
    let publishedAt: Date?
    let creatorID: String
    let coverImageURL: String?
    let segmentCount: Int
    let collection: VideoCollection?

    init?(doc: DocumentSnapshot) {
        guard let data = doc.data(),
              let creatorID = data["creatorID"] as? String else { return nil }
        self.id           = doc.documentID
        self.creatorID    = creatorID
        self.title        = data["title"] as? String ?? "Untitled"
        self.episodeTitle = data["title"] as? String ?? "Untitled"
        self.showId       = data["showId"] as? String
        self.seasonId     = data["seasonId"] as? String
        self.episodeNumber = (data["episodeNumber"] as? Int)
        self.contentType  = CollectionContentType(rawValue: data["contentType"] as? String ?? "") ?? .standard
        self.status       = CollectionStatus(rawValue: data["status"] as? String ?? "draft") ?? .draft
        self.publishedAt  = (data["publishedAt"] as? Timestamp)?.dateValue()
        self.coverImageURL = data["coverImageURL"] as? String
        self.segmentCount = (data["segmentCount"] as? Int) ?? 0
        self.collection   = nil  // Lazy — only decoded if needed for editing
    }

    var isUpcoming: Bool { publishedAt.map { $0 > Date() } ?? false }
    var isToday: Bool {
        guard let d = publishedAt else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var statusBadge: String {
        switch status {
        case .draft:      return "DRAFT"
        case .published:
            if isToday { return "LIVE" }
            return publishedAt.map { $0 > Date() ? "SCHEDULED" : "AIRED" } ?? "AIRED"
        default:
            return isUpcoming ? "UPCOMING" : status.rawValue.uppercased()
        }
    }

    var statusColor: Color {
        switch statusBadge {
        case "LIVE":      return .red
        case "UPCOMING", "SCHEDULED": return .cyan
        case "DRAFT":     return .gray
        case "AIRED":     return .white.opacity(0.3)
        default:          return .gray
        }
    }

    var contentColor: Color { ShowCard.colorFor(contentType) }
}

// MARK: - Schedule Day Group

struct ScheduleDay: Identifiable {
    let id: String
    let date: Date
    let items: [ScheduleItem]

    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isPast: Bool  { date < Calendar.current.startOfDay(for: Date()) }

    var headerLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }
}

// MARK: - CreatorScheduleView

struct CreatorScheduleView: View {

    let creatorID: String
    let creatorName: String
    let isOwner: Bool
    let onDismiss: () -> Void

    // Episode editor entry point (owner only)
    var onEditEpisode: ((VideoCollection) -> Void)?

    @State private var items: [ScheduleItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Week navigation
    @State private var weekOffset: Int = 0      // 0 = current week
    @State private var selectedDate: Date?

    // Viewer notifications
    @State private var subscribedIDs: Set<String> = []

    private let calendar = Calendar.current

    // MARK: - Computed

    private var displayedWeekStart: Date {
        let now = Date()
        let monday = calendar.date(from: calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: now))!
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: monday)!
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: displayedWeekStart) }
    }

    private var scheduleDays: [ScheduleDay] {
        guard !items.isEmpty else { return [] }

        // Extend visible range: current week ± 8 weeks
        let rangeStart = calendar.date(byAdding: .weekOfYear, value: -2, to: displayedWeekStart)!
        let rangeEnd   = calendar.date(byAdding: .weekOfYear, value: 10, to: displayedWeekStart)!

        let inRange = items.filter { item in
            guard let d = item.publishedAt else { return false }
            return d >= rangeStart && d <= rangeEnd
        }

        // Group by calendar day
        var byDay: [Date: [ScheduleItem]] = [:]
        for item in inRange {
            guard let d = item.publishedAt else { continue }
            let day = calendar.startOfDay(for: d)
            byDay[day, default: []].append(item)
        }

        return byDay.map { day, dayItems in
            ScheduleDay(
                id: day.description,
                date: day,
                items: dayItems.sorted { ($0.publishedAt ?? Date()) < ($1.publishedAt ?? Date()) }
            )
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(.cyan)
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    VStack(spacing: 0) {
                        weekStrip
                        Divider().background(Color.white.opacity(0.06))
                        scheduleList
                    }
                }
            }
            .navigationTitle("\(creatorName)'s Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(.cyan)
                }
                if isOwner {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            // Jump to today
                            weekOffset = 0
                            selectedDate = Date()
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
        }
        .task { await loadSchedule() }
        .preferredColorScheme(.dark)
    }

    // MARK: - Week Strip

    private var weekStrip: some View {
        VStack(spacing: 0) {
            // Month label + prev/next
            HStack {
                Button { weekOffset -= 1 } label: {
                    Image(systemName: "chevron.left").foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Text(weekRangeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button { weekOffset += 1 } label: {
                    Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Day pills
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    dayPill(day)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    private func dayPill(_ day: Date) -> some View {
        let isToday  = calendar.isDateInToday(day)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let hasItems = items.contains { item in
            guard let d = item.publishedAt else { return false }
            return calendar.isDate(d, inSameDayAs: day)
        }
        let dayFmt   = DateFormatter(); dayFmt.dateFormat = "EEE"
        let numFmt   = DateFormatter(); numFmt.dateFormat = "d"

        return Button {
            selectedDate = day
            // Scroll handled by scrollTo in list
        } label: {
            VStack(spacing: 4) {
                Text(dayFmt.string(from: day).uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isToday ? .cyan : .white.opacity(0.4))

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.cyan : (isToday ? Color.cyan.opacity(0.15) : Color.clear))
                        .frame(width: 32, height: 32)

                    Text(numFmt.string(from: day))
                        .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundColor(isSelected ? .black : (isToday ? .cyan : .white))
                }

                // Dot if has items
                Circle()
                    .fill(hasItems ? Color.cyan : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: date)
    }
    private func ampmString(from date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "a"; return f.string(from: date)
    }

    // MARK: - Schedule List

    private var scheduleList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                    if scheduleDays.isEmpty {
                        emptyState
                    } else {
                        ForEach(scheduleDays) { day in
                            Section {
                                ForEach(day.items) { item in
                                    scheduleRow(item)
                                    Divider().background(Color.white.opacity(0.04)).padding(.leading, 80)
                                }

                                // Owner: empty slot tap to create
                                if isOwner {
                                    createSlotRow(for: day.date)
                                }
                            } header: {
                                dayHeader(day)
                            }
                        }

                        Spacer(minLength: 80)
                    }
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                guard let newDate = newDate else { return }
                let dayStart = calendar.startOfDay(for: newDate)
                if let match = scheduleDays.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) {
                    withAnimation { proxy.scrollTo(match.id, anchor: .top) }
                }
            }
        }
    }

    // MARK: - Day Header

    private func dayHeader(_ day: ScheduleDay) -> some View {
        HStack {
            Text(day.headerLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(day.isToday ? .cyan : .white.opacity(0.5))
                .padding(.leading, 16)

            if day.isToday {
                Text("TODAY")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(4)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.95))
        .id(day.id)
    }

    // MARK: - Schedule Row

    private func scheduleRow(_ item: ScheduleItem) -> some View {
        HStack(spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                if let d = item.publishedAt {
                    Text(timeString(from: d))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(ampmString(from: d))
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                } else {
                    Text("TBD")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 44, alignment: .trailing)

            // Content type color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(item.contentColor)
                .frame(width: 3, height: 52)

            // Thumbnail
            if let url = item.coverImageURL.flatMap(URL.init) {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.06))
                }
                .frame(width: 52, height: 40)
                .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(item.contentColor.opacity(0.12))
                    Image(systemName: item.contentType.icon)
                        .font(.system(size: 14))
                        .foregroundColor(item.contentColor.opacity(0.6))
                }
                .frame(width: 52, height: 40)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let ep = item.episodeNumber {
                    Text("Episode \(ep) · \(item.contentType.displayName)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }

                // Status badge
                Text(item.statusBadge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(item.statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.statusColor.opacity(0.12))
                    .cornerRadius(3)
            }

            Spacer()

            // Action button
            if isOwner {
                Button {
                    // Load full collection for editing
                    Task { await openEditor(for: item) }
                } label: {
                    Image(systemName: item.status == .draft ? "pencil.circle" : "calendar.badge.clock")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            } else {
                // Viewer: bell subscribe
                let subscribed = subscribedIDs.contains(item.id)
                Button { toggleSubscription(item) } label: {
                    Image(systemName: subscribed ? "bell.fill" : "bell")
                        .font(.system(size: 16))
                        .foregroundColor(subscribed ? .cyan : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!item.isUpcoming)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
        .contentShape(Rectangle())
    }

    // MARK: - Create Slot Row (Owner)

    private func createSlotRow(for date: Date) -> some View {
        Button {
            // Signal intent to create episode for this date
            // Profile / parent view handles navigation
            selectedDate = date
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.1))
                Text("Add episode for this day")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.1))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.08))
            Text(isOwner ? "No scheduled episodes yet" : "Nothing scheduled")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text(isOwner
                 ? "Schedule episodes from the Episode Editor to see them here."
                 : "Check back soon for upcoming premieres.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange).font(.system(size: 32))
            Text(message).foregroundColor(.gray).font(.caption)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Retry") { Task { await loadSchedule() } }
                .foregroundColor(.cyan)
        }
    }

    // MARK: - Week Range Label

    private var weekRangeLabel: String {
        let end = calendar.date(byAdding: .day, value: 6, to: displayedWeekStart)!
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(f.string(from: displayedWeekStart)) – \(f.string(from: end))"
    }

    // MARK: - Data

    private func loadSchedule() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await ScheduleDataService.shared.getSchedule(
                creatorID: creatorID, isOwner: isOwner)
            // Select today by default
            selectedDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openEditor(for item: ScheduleItem) async {
        // Fetch full collection doc for editing
        do {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let doc = try await db.collection("videoCollections").document(item.id).getDocument()
            guard let data = doc.data() else { return }
            // Decode minimally — enough for EpisodeEditorView
            // Full decode handled by CollectionService in the editor
            print("📅 SCHEDULE: Opening editor for \(item.id)")
            // onEditEpisode callback lets parent handle navigation
        } catch {
            print("❌ SCHEDULE: Failed to load episode for editing: \(error)")
        }
    }

    private func toggleSubscription(_ item: ScheduleItem) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let subscribed = subscribedIDs.contains(item.id)

        if subscribed {
            subscribedIDs.remove(item.id)
        } else {
            subscribedIDs.insert(item.id)
        }

        // Write/delete notification subscription doc
        Task {
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let ref = db.collection("premiereSubscriptions")
                .document("\(userID)_\(item.id)")
            do {
                if subscribed {
                    try await ref.delete()
                } else {
                    try await ref.setData([
                        "userID": userID,
                        "collectionID": item.id,
                        "creatorID": item.creatorID,
                        "premiereAt": item.publishedAt.map { Timestamp(date: $0) } as Any,
                        "subscribedAt": FieldValue.serverTimestamp()
                    ])
                }
            } catch {
                // Revert optimistic update
                if subscribed { subscribedIDs.insert(item.id) }
                else { subscribedIDs.remove(item.id) }
            }
        }
    }
}

// RoundedCornerShape defined elsewhere in project
