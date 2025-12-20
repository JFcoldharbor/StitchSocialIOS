//
//  ThreadComposer.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Creation Interface
//  Dependencies: VideoCoordinator (Layer 6), CoreVideoMetadata (Layer 1), BoundedVideoContainer
//  Features: Working video preview, hashtag input, metadata editing, AI result integration
//  FIXED: Now passes manual title/description to VideoCoordinator
//  UPDATED: Added user tagging system
//  UPDATED: Added announcement system for admin accounts (developers@stitchsocial.me)
//  FIXED: Capture email UPFRONT to avoid race condition with auth state
//  UPDATED: Full announcement scheduling with start/end dates and repeat modes
//

import SwiftUI
import AVFoundation
import AVKit
import Combine
import FirebaseAuth

struct ThreadComposer: View {
    
    // MARK: - Properties
    
    let recordedVideoURL: URL
    let recordingContext: RecordingContext
    let aiResult: VideoAnalysisResult?
    let onVideoCreated: (CoreVideoMetadata) -> Void
    let onCancel: () -> Void
    
    // MARK: - State
    
    @StateObject private var videoCoordinator = VideoCoordinator(
        videoService: VideoService(),
        userService: UserService(),
        aiAnalyzer: AIVideoAnalyzer(),
        uploadService: VideoUploadService(),
        cachingService: nil
    )
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var hashtags: [String] = []
    @State private var taggedUserIDs: [String] = []
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Hashtag input state
    @State private var newHashtagText = ""
    
    // User tagging state
    @State private var showingUserTagSheet = false
    
    // MARK: - Announcement State
    @State private var isAnnouncement: Bool = false
    @State private var announcementPriority: AnnouncementPriority = .standard
    @State private var announcementType: AnnouncementType = .update
    @State private var minimumWatchSeconds: Int = 5
    
    // MARK: - Announcement Scheduling State (NEW)
    @State private var announcementStartDate: Date = Date()
    @State private var announcementEndDate: Date? = nil
    @State private var hasEndDate: Bool = false
    @State private var repeatMode: AnnouncementRepeatMode = .once
    @State private var maxDailyShows: Int = 1
    @State private var minHoursBetweenShows: Double = 6.0
    @State private var maxTotalShows: Int? = nil
    @State private var hasMaxTotalShows: Bool = false
    
    // FIXED: Capture email on view appear to avoid race conditions
    @State private var capturedUserEmail: String = ""
    @State private var capturedUserId: String = ""
    
    // Video preview state
    @State private var sharedPlayer: AVPlayer?
    @State private var isPlaying = false
    
    // AI Analysis state
    @State private var isAnalyzing = false
    @State private var hasAnalyzed = false
    
    // Video aspect ratio state
    @State private var videoAspectRatio: CGFloat = 9.0/16.0
    @State private var isLandscapeVideo: Bool = false
    
    // MARK: - Constants
    
    private let maxTitleLength = 100
    private let maxDescriptionLength = 500
    private let maxHashtags = 10
    private let maxTaggedUsers = 10
    
    // MARK: - Computed Properties
    
    // FIXED: Use captured email instead of live lookup
    private var canCreateAnnouncement: Bool {
        let result = AnnouncementVideoHelper.canCreateAnnouncement(email: capturedUserEmail)
        return result
    }
    
    private var canPost: Bool {
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               title.count <= maxTitleLength &&
               description.count <= maxDescriptionLength &&
               !isCreating
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            if isCreating {
                creationProgressView
            } else {
                mainContent
            }
        }
        .onAppear {
            // FIXED: Capture auth state immediately on appear
            captureAuthState()
            
            setupSharedVideoPlayer()
            detectVideoAspectRatio()
            
            if aiResult == nil && !hasAnalyzed {
                runAIAnalysis()
            } else {
                setupInitialContent()
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingUserTagSheet) {
            UserTagSheet(
                onSelectUsers: { userIDs in
                    taggedUserIDs = userIDs
                    showingUserTagSheet = false
                },
                onDismiss: {
                    showingUserTagSheet = false
                },
                alreadyTaggedIDs: taggedUserIDs
            )
        }
    }
    
    // MARK: - Capture Auth State
    
    private func captureAuthState() {
        // Get email directly from Firebase Auth
        let firebaseEmail = Auth.auth().currentUser?.email ?? ""
        let firebaseUID = Auth.auth().currentUser?.uid ?? ""
        
        capturedUserEmail = firebaseEmail
        capturedUserId = firebaseUID
        
        print("📢 THREAD COMPOSER: Captured auth state")
        print("📢 THREAD COMPOSER: Email = '\(capturedUserEmail)'")
        print("📢 THREAD COMPOSER: UID = '\(capturedUserId)'")
        print("📢 THREAD COMPOSER: Can create announcement = \(canCreateAnnouncement)")
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Video Preview
            videoPreview
                .frame(height: isLandscapeVideo ? 150 : 200)
            
            // Content Editor
            ScrollView {
                VStack(spacing: 20) {
                    titleEditor
                    descriptionEditor
                    hashtagEditor
                    userTagEditor
                    
                    // Announcement Section (only for admin accounts)
                    announcementSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            
            Spacer(minLength: 0)
            
            // Post Button
            postButton
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button("Cancel") {
                cleanupPlayer()
                onCancel()
            }
            .foregroundColor(.white)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(recordingContext.contextDisplayTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        Text("Analyzing...")
                            .font(.caption)
                            .foregroundColor(.cyan)
                    }
                }
            }
            
            Spacer()
            
            // Skip AI button (if analyzing)
            if isAnalyzing {
                Button("Skip") {
                    skipAIAnalysis()
                }
                .foregroundColor(.cyan)
            } else {
                // Placeholder for alignment
                Text("Cancel")
                    .foregroundColor(.clear)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Video Preview
    
    private var videoPreview: some View {
        ZStack {
            if let player = sharedPlayer {
                VideoPlayer(player: player)
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .onTapGesture {
                        togglePlayback()
                    }
                
                // Play/Pause overlay
                if !isPlaying {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.8))
                        .onTapGesture {
                            togglePlayback()
                        }
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Title Editor
    
    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Title")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("*")
                    .foregroundColor(.red)
                
                Spacer()
                
                Text("\(title.count)/\(maxTitleLength)")
                    .font(.caption)
                    .foregroundColor(title.count > maxTitleLength ? .red : .gray)
            }
            
            TextField("Enter video title...", text: $title)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .accentColor(.blue)
                .onChange(of: title) { _, newValue in
                    if newValue.count > maxTitleLength {
                        title = String(newValue.prefix(maxTitleLength))
                    }
                }
        }
    }
    
    // MARK: - Description Editor
    
    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(description.count)/\(maxDescriptionLength)")
                    .font(.caption)
                    .foregroundColor(description.count > maxDescriptionLength ? .red : .gray)
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 100)
                
                TextEditor(text: $description)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.clear)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .onChange(of: description) { _, newValue in
                        if newValue.count > maxDescriptionLength {
                            description = String(newValue.prefix(maxDescriptionLength))
                        }
                    }
                
                if description.isEmpty {
                    Text("Enter description...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - Hashtag Editor
    
    private var hashtagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hashtags")
                .font(.headline)
                .foregroundColor(.white)
            
            if !hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hashtags, id: \.self) { hashtag in
                            HStack(spacing: 4) {
                                Text("#\(hashtag)")
                                    .foregroundColor(.white)
                                
                                Button {
                                    removeHashtag(hashtag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(16)
                        }
                    }
                }
            }
            
            if hashtags.count < maxHashtags {
                HStack {
                    TextField("Add hashtag...", text: $newHashtagText)
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .accentColor(.blue)
                        .onSubmit {
                            addHashtag()
                        }
                    
                    Button("Add") {
                        addHashtag()
                    }
                    .disabled(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(newHashtagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - User Tag Editor
    
    private var userTagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tag Users")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(taggedUserIDs.count)/\(maxTaggedUsers)")
                    .font(.caption)
                    .foregroundColor(taggedUserIDs.count >= maxTaggedUsers ? .orange : .gray)
            }
            
            if !taggedUserIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(taggedUserIDs, id: \.self) { userID in
                            TaggedUserChip(userID: userID) {
                                removeTag(userID)
                            }
                        }
                    }
                }
            }
            
            Button {
                showingUserTagSheet = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16))
                    
                    Text(taggedUserIDs.isEmpty ? "Tag Users" : "Edit Tags")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.cyan)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(taggedUserIDs.count >= maxTaggedUsers && taggedUserIDs.isEmpty)
        }
    }
    
    // MARK: - Announcement Section
    
    @ViewBuilder
    private var announcementSection: some View {
        if canCreateAnnouncement {
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
                    
                    // Admin badge
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
                        // SECTION: Basic Settings
                        announcementBasicSettings
                        
                        // SECTION: Scheduling
                        announcementSchedulingSection
                        
                        // SECTION: Repeat Settings (only for non-once modes)
                        if repeatMode != .once {
                            announcementRepeatSettings
                        }
                        
                        // Preview badge
                        HStack {
                            Spacer()
                            announcementPreviewBadge
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        // Schedule summary
                        announcementScheduleSummary
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
            }
        } else {
            // Debug: Show why admin section isn't visible
            EmptyView()
                .onAppear {
                    print("📢 THREAD COMPOSER: Admin section NOT showing")
                    print("📢 THREAD COMPOSER: capturedUserEmail = '\(capturedUserEmail)'")
                    print("📢 THREAD COMPOSER: canCreateAnnouncement = \(canCreateAnnouncement)")
                }
        }
    }
    
    // MARK: - Announcement Basic Settings
    
    private var announcementBasicSettings: some View {
        VStack(spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.cyan)
                Text("Basic Settings")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Priority Picker
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
            
            // Type Picker
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
            
            // Minimum Watch Time
            HStack {
                Text("Min Watch Time")
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        if minimumWatchSeconds > 3 {
                            minimumWatchSeconds -= 1
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("\(minimumWatchSeconds)s")
                        .foregroundColor(.white)
                        .frame(width: 40)
                    
                    Button {
                        if minimumWatchSeconds < 30 {
                            minimumWatchSeconds += 1
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
    }
    
    // MARK: - Announcement Scheduling Section
    
    private var announcementSchedulingSection: some View {
        VStack(spacing: 12) {
            // Section Header
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
            
            // End Date Toggle + Picker
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
                        // Default to 1 week from start
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
            
            // Repeat Mode Picker
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
            
            // Repeat mode description
            Text(repeatMode.description)
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Announcement Repeat Settings
    
    private var announcementRepeatSettings: some View {
        VStack(spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: "repeat")
                    .foregroundColor(.purple)
                Text("Repeat Settings")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.top, 8)
            
            // Max Shows Per Day
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max per Day")
                        .foregroundColor(.gray)
                    Text("Times shown daily")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                }
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        if maxDailyShows > 1 {
                            maxDailyShows -= 1
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("\(maxDailyShows)")
                        .foregroundColor(.white)
                        .frame(width: 30)
                    
                    Button {
                        if maxDailyShows < 10 {
                            maxDailyShows += 1
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
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
                HStack(spacing: 12) {
                    Button {
                        if minHoursBetweenShows > 1 {
                            minHoursBetweenShows -= 1
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Text("\(Int(minHoursBetweenShows))h")
                        .foregroundColor(.white)
                        .frame(width: 40)
                    
                    Button {
                        if minHoursBetweenShows < 24 {
                            minHoursBetweenShows += 1
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            
            // Max Total Shows (Optional)
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
                        HStack(spacing: 12) {
                            Button {
                                if let current = maxTotalShows, current > 2 {
                                    maxTotalShows = current - 1
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Text("\(total)")
                                .foregroundColor(.white)
                                .frame(width: 30)
                            
                            Button {
                                if let current = maxTotalShows, current < 100 {
                                    maxTotalShows = current + 1
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Announcement Schedule Summary
    
    private var announcementScheduleSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.cyan)
                Text("Schedule Summary")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Start info
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Starts: \(formatDate(announcementStartDate))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // End info
                if hasEndDate, let endDate = announcementEndDate {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("Ends: \(formatDate(endDate))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Duration
                    let days = Calendar.current.dateComponents([.day], from: announcementStartDate, to: endDate).day ?? 0
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("Duration: \(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "infinity")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        Text("Runs indefinitely")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                // Repeat info
                if repeatMode != .once {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        Text("Up to \(maxDailyShows)x/day, \(Int(minHoursBetweenShows))h apart")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if let total = maxTotalShows {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Max \(total) total shows per user")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var announcementPreviewBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: announcementType.icon)
                .font(.caption)
            Text(announcementType.displayName.uppercased())
                .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(announcementPriorityColor)
        .foregroundColor(.white)
        .clipShape(Capsule())
    }
    
    private var announcementPriorityColor: Color {
        switch announcementPriority {
        case .critical: return .red
        case .high: return .orange
        case .standard: return .blue
        case .low: return .gray
        }
    }
    
    // MARK: - Post Button
    
    private var postButton: some View {
        Button {
            createThread()
        } label: {
            HStack {
                if isAnnouncement {
                    Image(systemName: "megaphone.fill")
                }
                Text(isAnnouncement ? "Post Announcement" : "Post Thread")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Group {
                    if canPost {
                        if isAnnouncement {
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
            )
            .cornerRadius(20)
        }
        .disabled(!canPost)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Creation Progress View
    
    private var creationProgressView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            VStack(spacing: 8) {
                Text(isAnnouncement ? "Creating announcement..." : "Creating your thread...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(videoCoordinator.currentTask)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            
            ProgressView(value: videoCoordinator.overallProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: isAnnouncement ? .orange : .blue))
                .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Thread Creation (FIXED: Use captured email)
    
    private func createThread() {
        guard !isCreating else { return }
        
        // FIXED: Capture auth state again in case it changed
        let emailToUse = capturedUserEmail.isEmpty ? (Auth.auth().currentUser?.email ?? "") : capturedUserEmail
        let shouldCreateAnnouncement = isAnnouncement && AnnouncementVideoHelper.canCreateAnnouncement(email: emailToUse)
        
        print("🎬 CREATION: Starting - pausing video player")
        print("📢 CREATION: isAnnouncement = \(isAnnouncement)")
        print("📢 CREATION: emailToUse = '\(emailToUse)'")
        print("📢 CREATION: shouldCreateAnnouncement = \(shouldCreateAnnouncement)")
        
        sharedPlayer?.pause()
        isPlaying = false
        isCreating = true
        
        Task {
            do {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("✏️ MANUAL CONTENT: Passing to VideoCoordinator")
                print("✏️ TITLE: '\(trimmedTitle)'")
                print("✏️ DESCRIPTION: '\(trimmedDescription)'")
                print("🏷️ TAGGED USERS: \(taggedUserIDs.count) users")
                print("📢 IS ANNOUNCEMENT: \(isAnnouncement)")
                
                let authService = AuthService()
                let currentUserID = authService.currentUser?.id ?? Auth.auth().currentUser?.uid ?? "unknown"
                let currentUserTier = authService.currentUser?.tier ?? .rookie
                
                print("🔑 AUTH: User ID = '\(currentUserID)'")
                print("🔑 AUTH: User Tier = '\(currentUserTier.rawValue)'")
                
                let createdVideo = try await videoCoordinator.processVideoCreation(
                    recordedVideoURL: recordedVideoURL,
                    recordingContext: recordingContext,
                    userID: currentUserID,
                    userTier: currentUserTier,
                    manualTitle: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    manualDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    taggedUserIDs: taggedUserIDs
                )
                
                // FIXED: Use the email we captured, create announcement
                if shouldCreateAnnouncement {
                    print("📢 ANNOUNCEMENT: About to create announcement...")
                    await createAnnouncementForVideo(createdVideo, creatorEmail: emailToUse)
                } else {
                    print("📢 ANNOUNCEMENT: Skipping - shouldCreateAnnouncement=\(shouldCreateAnnouncement)")
                }
                
                await MainActor.run {
                    print("✅ THREAD CREATION: Success!")
                    print("✅ FINAL TITLE: '\(createdVideo.title)'")
                    print("✅ FINAL DESCRIPTION: '\(createdVideo.description)'")
                    print("✅ TAGGED USERS: \(createdVideo.taggedUserIDs.count)")
                    if shouldCreateAnnouncement {
                        print("📢 ANNOUNCEMENT: Creation attempted")
                    }
                    isCreating = false
                    onVideoCreated(createdVideo)
                }
                
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create thread: \(error.localizedDescription)"
                    showError = true
                    print("❌ THREAD CREATION: Failed - \(error.localizedDescription)")
                    
                    isPlaying = true
                    sharedPlayer?.play()
                }
            }
        }
    }
    
    // MARK: - Create Announcement (UPDATED: Now passes all scheduling parameters)
    
    private func createAnnouncementForVideo(_ video: CoreVideoMetadata, creatorEmail: String) async {
        print("📢 CREATE ANNOUNCEMENT: Starting...")
        print("📢 CREATE ANNOUNCEMENT: videoId = \(video.id)")
        print("📢 CREATE ANNOUNCEMENT: creatorEmail = '\(creatorEmail)'")
        print("📢 CREATE ANNOUNCEMENT: title = '\(video.title)'")
        print("📢 CREATE ANNOUNCEMENT: startDate = \(announcementStartDate)")
        print("📢 CREATE ANNOUNCEMENT: endDate = \(String(describing: hasEndDate ? announcementEndDate : nil))")
        print("📢 CREATE ANNOUNCEMENT: repeatMode = \(repeatMode.rawValue)")
        
        do {
            let announcement = try await AnnouncementService.shared.createAnnouncement(
                videoId: video.id,
                creatorEmail: creatorEmail,
                creatorId: video.creatorID,
                title: video.title,
                message: video.description.isEmpty ? nil : video.description,
                priority: announcementPriority,
                type: announcementType,
                targetAudience: .all,
                startDate: announcementStartDate,
                endDate: hasEndDate ? announcementEndDate : nil,
                minimumWatchSeconds: minimumWatchSeconds,
                isDismissable: true,
                requiresAcknowledgment: false,
                repeatMode: repeatMode,
                maxDailyShows: maxDailyShows,
                minHoursBetweenShows: minHoursBetweenShows,
                maxTotalShows: maxTotalShows
            )
            print("📢 ANNOUNCEMENT CREATED: \(announcement.id)")
            print("📢 PRIORITY: \(announcementPriority.displayName)")
            print("📢 TYPE: \(announcementType.displayName)")
            print("📢 MIN WATCH: \(minimumWatchSeconds)s")
            print("📢 START: \(announcement.startDate)")
            print("📢 END: \(String(describing: announcement.endDate))")
            print("📢 REPEAT MODE: \(announcement.repeatMode.rawValue)")
            print("📢 MAX DAILY: \(announcement.maxDailyShows)")
            print("📢 MIN HOURS BETWEEN: \(announcement.minHoursBetweenShows)")
            print("📢 MAX TOTAL: \(String(describing: announcement.maxTotalShows))")
        } catch {
            print("⚠️ ANNOUNCEMENT CREATION FAILED: \(error)")
            print("⚠️ ERROR DETAILS: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Video Player Setup
    
    private func setupSharedVideoPlayer() {
        print("🎬 SETUP: Creating shared video player")
        let player = AVPlayer(url: recordedVideoURL)
        
        player.isMuted = false
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        
        sharedPlayer = player
        
        if !isAnalyzing {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
            print("🎬 SETUP: Player ready but paused - waiting for AI analysis")
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard let player = self.sharedPlayer else { return }
                
                player.seek(to: .zero) { _ in
                    if self.isPlaying {
                        player.play()
                    }
                }
            }
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            sharedPlayer?.pause()
        } else {
            sharedPlayer?.play()
        }
        isPlaying.toggle()
    }
    
    private func cleanupPlayer() {
        sharedPlayer?.pause()
        sharedPlayer = nil
        isPlaying = false
    }
    
    // MARK: - Video Aspect Ratio Detection
    
    private func detectVideoAspectRatio() {
        let asset = AVAsset(url: recordedVideoURL)
        
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let videoTrack = tracks.first else {
                    print("⚠️ ASPECT RATIO: No video track found, using default 9:16")
                    return
                }
                
                let naturalSize = try await videoTrack.load(.naturalSize)
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                
                let transformedSize = naturalSize.applying(preferredTransform)
                let width = abs(transformedSize.width)
                let height = abs(transformedSize.height)
                
                guard height > 0 else { return }
                
                await MainActor.run {
                    self.videoAspectRatio = width / height
                    self.isLandscapeVideo = self.videoAspectRatio > 1.0
                    
                    let orientation = self.videoAspectRatio > 1.0 ? "Landscape" : (self.videoAspectRatio < 0.9 ? "Portrait" : "Square")
                    print("📐 ASPECT RATIO: \(orientation) - \(String(format: "%.2f", self.videoAspectRatio))")
                }
            } catch {
                print("⚠️ ASPECT RATIO: Failed to detect - \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - AI Analysis
    
    private func runAIAnalysis() {
        guard !hasAnalyzed else { return }
        
        isAnalyzing = true
        sharedPlayer?.pause()
        isPlaying = false
        
        Task {
            do {
                print("🤖 AI ANALYSIS: Starting...")
                
                let authService = AuthService()
                let result = try await AIVideoAnalyzer().analyzeVideo(
                    url: recordedVideoURL,
                    userID: authService.currentUser?.id ?? "unknown"
                )
                
                await MainActor.run {
                    isAnalyzing = false
                    hasAnalyzed = true
                    
                    if let result = result {
                        title = result.title
                        description = result.description
                        hashtags = Array(result.hashtags.prefix(maxHashtags))
                        print("✅ THREAD COMPOSER: AI analysis successful - '\(result.title)'")
                    } else {
                        setupInitialContent()
                        print("⚠️ THREAD COMPOSER: AI analysis failed - using defaults")
                    }
                    
                    print("🎬 AI ANALYSIS: Complete - resuming video player")
                    isPlaying = true
                    sharedPlayer?.play()
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    hasAnalyzed = true
                    setupInitialContent()
                    print("❌ THREAD COMPOSER: AI analysis error - \(error.localizedDescription)")
                    
                    print("🎬 AI ANALYSIS: Error - resuming video player")
                    isPlaying = true
                    sharedPlayer?.play()
                }
            }
        }
    }
    
    private func skipAIAnalysis() {
        print("⏭️ THREAD COMPOSER: AI analysis skipped by user")
        isAnalyzing = false
        hasAnalyzed = true
        setupInitialContent()
        isPlaying = true
        sharedPlayer?.play()
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialContent() {
        if let aiResult = aiResult {
            title = aiResult.title
            description = aiResult.description
            hashtags = Array(aiResult.hashtags.prefix(maxHashtags))
        } else {
            title = getDefaultTitle()
            description = ""
            hashtags = []
        }
    }
    
    private func getDefaultTitle() -> String {
        switch recordingContext {
        case .newThread:
            return "New Thread"
        case .stitchToThread(_, let info):
            return "Stitching to \(info.creatorName)"
        case .replyToVideo(_, let info):
            return "Reply to \(info.creatorName)"
        case .continueThread(_, let info):
            return "Continuing \(info.title)"
        }
    }
    
    // MARK: - Hashtag Methods
    
    private func addHashtag() {
        let cleaned = newHashtagText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard !cleaned.isEmpty, !hashtags.contains(cleaned), hashtags.count < maxHashtags else {
            newHashtagText = ""
            return
        }
        
        hashtags.append(cleaned)
        newHashtagText = ""
    }
    
    private func removeHashtag(_ hashtag: String) {
        hashtags.removeAll { $0 == hashtag }
    }
    
    // MARK: - Tag Methods
    
    private func removeTag(_ userID: String) {
        taggedUserIDs.removeAll { $0 == userID }
    }
}

// MARK: - Supporting Extensions

extension RecordingContext {
    var contextDisplayTitle: String {
        switch self {
        case .newThread:
            return "New Thread"
        case .stitchToThread:
            return "Stitch"
        case .replyToVideo:
            return "Reply"
        case .continueThread:
            return "Continue Thread"
        }
    }
}

// MARK: - Preview

#Preview {
    ThreadComposer(
        recordedVideoURL: URL(string: "file://test.mp4")!,
        recordingContext: .newThread,
        aiResult: nil,
        onVideoCreated: { _ in },
        onCancel: { }
    )
}
