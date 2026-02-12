//
//  AnnouncementSection.swift
//  StitchSocial
//
//  Created by James Garmon on 2/11/26.
//


//
//  AnnouncementSection.swift
//  StitchSocial
//
//  Layer 8: Views - Admin Announcement Configuration
//  Extracted from ThreadComposer
//  Dependencies: AnnouncementService, AnnouncementVideoHelper
//  Features: Priority, type, scheduling, repeat settings for announcements
//  Only visible to admin accounts (developers@stitchsocial.me, james@stitchsocial.me)
//

import SwiftUI

struct AnnouncementSection: View {
    
    @Binding var isAnnouncement: Bool
    @Binding var announcementPriority: AnnouncementPriority
    @Binding var announcementType: AnnouncementType
    @Binding var minimumWatchSeconds: Int
    @Binding var announcementStartDate: Date
    @Binding var announcementEndDate: Date?
    @Binding var hasEndDate: Bool
    @Binding var repeatMode: AnnouncementRepeatMode
    @Binding var maxDailyShows: Int
    @Binding var minHoursBetweenShows: Double
    @Binding var maxTotalShows: Int?
    @Binding var hasMaxTotalShows: Bool
    
    let canCreateAnnouncement: Bool
    
    var body: some View {
        if canCreateAnnouncement {
            announcementContent
        }
    }
    
    // MARK: - Main Content
    
    private var announcementContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 8)
            
            // Header
            HStack {
                Image(systemName: "megaphone.fill")
                    .foregroundColor(.orange)
                Text("Admin Options")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("ADMIN")
                    .font(.caption2.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(4)
            }
            
            // Toggle
            Toggle(isOn: $isAnnouncement) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make this an Announcement")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("All users must view this at least once")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .tint(.orange)
            
            // Options (only show when announcement is ON)
            if isAnnouncement {
                VStack(spacing: 16) {
                    basicSettings
                    schedulingSection
                    
                    if repeatMode != .once {
                        repeatSettings
                    }
                    
                    HStack {
                        Spacer()
                        previewBadge
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    scheduleSummary
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Basic Settings
    
    private var basicSettings: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.cyan)
                Text("Basic Settings")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Priority
            HStack {
                Text("Priority")
                    .foregroundColor(.gray)
                Spacer()
                Picker("Priority", selection: $announcementPriority) {
                    ForEach(AnnouncementPriority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            
            // Type
            HStack {
                Text("Type")
                    .foregroundColor(.gray)
                Spacer()
                Picker("Type", selection: $announcementType) {
                    ForEach(AnnouncementType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.displayName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            
            // Min Watch Time
            HStack {
                Text("Min Watch Time")
                    .foregroundColor(.gray)
                Spacer()
                stepper(value: $minimumWatchSeconds, range: 3...30, suffix: "s")
            }
        }
    }
    
    // MARK: - Scheduling
    
    private var schedulingSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.green)
                Text("Scheduling")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.top, 8)
            
            // Start Date
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Date")
                    .font(.caption)
                    .foregroundColor(.gray)
                DatePicker(
                    "",
                    selection: $announcementStartDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
                .tint(.green)
            }
            
            // End Date
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $hasEndDate) {
                    HStack {
                        Text("Set End Date")
                            .foregroundColor(.gray)
                        if hasEndDate {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }
                .tint(.green)
                .onChange(of: hasEndDate) { _, newValue in
                    if newValue && announcementEndDate == nil {
                        announcementEndDate = Calendar.current.date(byAdding: .day, value: 7, to: announcementStartDate)
                    }
                }
                
                if hasEndDate, let endDate = announcementEndDate {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { endDate },
                            set: { announcementEndDate = $0 }
                        ),
                        in: announcementStartDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .tint(.green)
                }
            }
            
            // Repeat Mode
            HStack {
                Text("Repeat")
                    .foregroundColor(.gray)
                Spacer()
                Picker("Repeat", selection: $repeatMode) {
                    ForEach(AnnouncementRepeatMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }
            
            Text(repeatMode.description)
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Repeat Settings
    
    private var repeatSettings: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "repeat")
                    .foregroundColor(.purple)
                Text("Repeat Settings")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.top, 8)
            
            // Max per Day
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max per Day")
                        .foregroundColor(.gray)
                    Text("Times shown daily")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
                stepper(value: $maxDailyShows, range: 1...10)
            }
            
            // Min Hours Between
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min Hours Apart")
                        .foregroundColor(.gray)
                    Text("Cooldown between shows")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
                stepperDouble(value: $minHoursBetweenShows, range: 1...24, suffix: "h")
            }
            
            // Lifetime Cap
            VStack(spacing: 8) {
                Toggle(isOn: $hasMaxTotalShows) {
                    HStack {
                        Text("Lifetime Cap")
                            .foregroundColor(.gray)
                        if hasMaxTotalShows {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.purple)
                                .font(.caption)
                        }
                    }
                }
                .tint(.purple)
                .onChange(of: hasMaxTotalShows) { _, newValue in
                    if newValue && maxTotalShows == nil {
                        maxTotalShows = 10
                    } else if !newValue {
                        maxTotalShows = nil
                    }
                }
                
                if hasMaxTotalShows, let total = maxTotalShows {
                    HStack {
                        Text("Max total shows")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.6))
                        Spacer()
                        stepper(
                            value: Binding(
                                get: { total },
                                set: { maxTotalShows = $0 }
                            ),
                            range: 2...100
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Preview Badge
    
    private var previewBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: announcementType.icon)
                .font(.caption)
            Text(announcementType.displayName.uppercased())
                .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(priorityColor)
        .foregroundColor(.white)
        .clipShape(Capsule())
    }
    
    private var priorityColor: Color {
        switch announcementPriority {
        case .critical: return .red
        case .high: return .orange
        case .standard: return .blue
        case .low: return .gray
        }
    }
    
    // MARK: - Schedule Summary
    
    private var scheduleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.cyan)
                Text("Schedule Summary")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                summaryRow(icon: "play.fill", color: .green, text: "Starts: \(formatDate(announcementStartDate))")
                
                if hasEndDate, let endDate = announcementEndDate {
                    summaryRow(icon: "stop.fill", color: .red, text: "Ends: \(formatDate(endDate))")
                    
                    let days = Calendar.current.dateComponents([.day], from: announcementStartDate, to: endDate).day ?? 0
                    summaryRow(icon: "clock", color: .orange, text: "Duration: \(days) day\(days == 1 ? "" : "s")")
                } else {
                    summaryRow(icon: "infinity", color: .purple, text: "Runs indefinitely")
                }
                
                if repeatMode != .once {
                    summaryRow(icon: "repeat", color: .purple, text: "Up to \(maxDailyShows)x/day, \(Int(minHoursBetweenShows))h apart")
                    
                    if let total = maxTotalShows {
                        summaryRow(icon: "number", color: .orange, text: "Max \(total) total shows per user")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Reusable Components
    
    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, suffix: String = "") -> some View {
        HStack(spacing: 12) {
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text("\(value.wrappedValue)\(suffix)")
                .foregroundColor(.white)
                .frame(width: 40)
            
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    private func stepperDouble(value: Binding<Double>, range: ClosedRange<Double>, suffix: String = "") -> some View {
        HStack(spacing: 12) {
            Button {
                if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text("\(Int(value.wrappedValue))\(suffix)")
                .foregroundColor(.white)
                .frame(width: 40)
            
            Button {
                if value.wrappedValue < range.upperBound { value.wrappedValue += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}