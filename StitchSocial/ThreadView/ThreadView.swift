//
//  ThreadView.swift
//  StitchSocial
//
//  Layer 8: Views - Thread Visualization
//  REDESIGNED: Discovery-style cards - thumbnail fills card, CreatorPill only
//

import SwiftUI
import AVFoundation

struct ThreadView: View {
    
    // MARK: - Properties
    let threadID: String
    let videoService: VideoService
    let userService: UserService
    let targetVideoID: String?
    
    @StateObject private var authService = AuthService()
    private let laneService = ConversationLaneService.shared
    
    // MARK: - State
    @State private var parentVideo: CoreVideoMetadata?
    @State private var childVideos: [CoreVideoMetadata] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentIndex: Int = 0
    @State private var selectedVideo: CoreVideoMetadata?
    @State private var showFullscreen = false
    @State private var showCarousel = false
    @State private var carouselVideos: [CoreVideoMetadata] = []
    @State private var directReplies: [CoreVideoMetadata] = []
    @State private var laneParticipantIDs: Set<String> = []  // The 2 users in current lane
    @State private var currentLaneAnchorID: String?          // The child video anchoring current lane
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isPanelExpanded = false
    @EnvironmentObject var muteManager: MuteContextManager
    
    @State private var selectedUserForProfile: String?
    @State private var showingProfileView = false
    
    // Pagination
    @State private var currentPage: Int = 0
    private let childrenPerPage = 20
    
    private var totalPages: Int {
        let total = childVideos.count
        return total == 0 ? 1 : (total + childrenPerPage - 1) / childrenPerPage
    }
    
    private var paginatedChildren: [CoreVideoMetadata] {
        let startIndex = currentPage * childrenPerPage
        let endIndex = min(startIndex + childrenPerPage, childVideos.count)
        guard startIndex < childVideos.count else { return [] }
        return Array(childVideos[startIndex..<endIndex])
    }
    
    private var allVisibleVideos: [CoreVideoMetadata] {
        guard let parent = parentVideo else { return [] }
        return [parent] + paginatedChildren
    }
    
    @Environment(\.dismiss) private var dismiss
    
    // Brand Colors
    private let brandCyan = Color(red: 0.0, green: 0.85, blue: 0.95)
    private let brandPurple = Color(red: 0.6, green: 0.4, blue: 0.95)
    private let brandPink = Color(red: 0.95, green: 0.4, blue: 0.7)
    private let brandCream = Color(red: 0.98, green: 0.97, blue: 0.96)
    private let brandDark = Color(red: 0.1, green: 0.1, blue: 0.15)
    
    init(
        threadID: String,
        videoService: VideoService,
        userService: UserService,
        targetVideoID: String? = nil
    ) {
        self.threadID = threadID
        self.videoService = videoService
        self.userService = userService
        self.targetVideoID = targetVideoID
    }
    
    private var allVideos: [CoreVideoMetadata] { allVisibleVideos }
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                marbleBackground(in: geometry)
                
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    VStack(spacing: 0) {
                        topBar
                        
                        Spacer()
                        
                        ZStack {
                            cardCarousel(in: geometry)
                            
                            HStack {
                                navButton(isLeft: true)
                                Spacer()
                                navButton(isLeft: false)
                            }
                            .padding(.horizontal, 8)
                        }
                        
                        Spacer()
                        
                        if totalPages > 1 {
                            pageNavigationView
                                .padding(.bottom, 12)
                        }
                        
                        if let parent = parentVideo {
                            Thread3DInfoPanel(
                                parentVideo: parent,
                                childVideos: paginatedChildren,
                                selectedVideo: allVideos.indices.contains(currentIndex) ? allVideos[currentIndex] : nil,
                                isExpanded: $isPanelExpanded,
                                onVideoTap: { video in
                                    openVideo(video)
                                },
                                onClose: { dismiss() }
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { loadThreadData() }
        .fullScreenCover(isPresented: $showFullscreen) {
            if let video = selectedVideo {
                FullscreenVideoView(
                    video: video,
                    overlayContext: .thread,
                    onDismiss: {
                        showFullscreen = false
                        selectedVideo = nil
                    }
                )
                .id(video.id)
            }
        }
        .fullScreenCover(isPresented: $showCarousel) {
            CardVideoCarouselView(
                videos: carouselVideos,
                parentVideo: parentVideo,
                startingIndex: selectedVideo.flatMap { v in carouselVideos.firstIndex(where: { $0.id == v.id }) } ?? 0,
                currentUserID: authService.currentUser?.id,
                directReplies: directReplies.isEmpty ? nil : directReplies,
                laneParticipantIDs: laneParticipantIDs,
                onSelectReply: { loadConversation(with: $0) }
            )
            .id("\(selectedVideo?.id ?? UUID().uuidString)-\(carouselVideos.count)")
        }
        .sheet(isPresented: $showingProfileView) {
            if let _ = selectedUserForProfile {
                ProfileView(authService: authService, userService: userService, videoService: videoService)
            }
        }
    }
    
    // MARK: - Nav Button
    
    private func navButton(isLeft: Bool) -> some View {
        let canNav = isLeft ? currentIndex > 0 : currentIndex < allVideos.count - 1
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if isLeft && currentIndex > 0 { currentIndex -= 1 }
                else if !isLeft && currentIndex < allVideos.count - 1 { currentIndex += 1 }
            }
        } label: {
            Image(systemName: isLeft ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(canNav ? brandDark.opacity(0.7) : brandDark.opacity(0.2))
                .shadow(color: .white.opacity(0.8), radius: 4)
        }
        .disabled(!canNav)
    }
    
    // MARK: - Marble Background
    
    private func marbleBackground(in geometry: GeometryProxy) -> some View {
        ZStack {
            brandCream
            
            Circle()
                .fill(brandCyan)
                .frame(width: geometry.size.width * 1.2)
                .blur(radius: 80)
                .opacity(0.4)
                .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.15)
            
            Circle()
                .fill(brandPurple)
                .frame(width: geometry.size.width * 1.0)
                .blur(radius: 90)
                .opacity(0.35)
                .position(x: geometry.size.width * 0.85, y: geometry.size.height * 0.4)
            
            Circle()
                .fill(brandPink)
                .frame(width: geometry.size.width * 0.9)
                .blur(radius: 70)
                .opacity(0.3)
                .position(x: geometry.size.width * 0.1, y: geometry.size.height * 0.75)
            
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.05)],
                center: .center,
                startRadius: geometry.size.width * 0.3,
                endRadius: geometry.size.width
            )
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(brandDark)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: Color.black.opacity(0.1), radius: 8)
                    )
            }
            
            Spacer()
            
            if !allVideos.isEmpty {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(currentIndex + 1)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("of")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("\(allVideos.count)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(currentIndex > 0 ? brandPurple : .secondary.opacity(0.3))
                        Text("swipe")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(currentIndex < allVideos.count - 1 ? brandPurple : .secondary.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.1), radius: 8)
                )
            }
            
            Spacer()
            
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
    
    // MARK: - Card Carousel
    
    private func cardCarousel(in geometry: GeometryProxy) -> some View {
        let cardWidth: CGFloat = isPanelExpanded ? geometry.size.width * 0.55 : geometry.size.width * 0.72
        let cardHeight: CGFloat = cardWidth * 1.4
        
        return ZStack {
            ForEach(Array(allVideos.enumerated()), id: \.element.id) { index, video in
                ThreadDiscoveryCard(
                    video: video,
                    isActive: index == currentIndex,
                    isOrigin: video.id == parentVideo?.id,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    brandCyan: brandCyan,
                    brandPurple: brandPurple,
                    isDragging: isDragging,
                    onTap: { openVideo(video) }
                )
                .scaleEffect(cardScale(for: index))
                .offset(x: cardOffset(for: index, cardWidth: cardWidth) + (index == currentIndex ? dragOffset : dragOffset * 0.3))
                .zIndex(cardZIndex(for: index))
                .opacity(cardOpacity(for: index))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentIndex)
            }
        }
        .frame(height: cardHeight + 40)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPanelExpanded)
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    isDragging = true
                    if abs(value.translation.width) > abs(value.translation.height) {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if (value.translation.width < -threshold || velocity < -100) && currentIndex < allVideos.count - 1 {
                            currentIndex += 1
                        } else if (value.translation.width > threshold || velocity > 100) && currentIndex > 0 {
                            currentIndex -= 1
                        }
                        dragOffset = 0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isDragging = false
                    }
                }
        )
    }
    
    // MARK: - Card Layout Helpers
    
    private func cardScale(for index: Int) -> CGFloat {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.88
        default: return 0.75
        }
    }
    
    private func cardOffset(for index: Int, cardWidth: CGFloat) -> CGFloat {
        let diff = CGFloat(index - currentIndex)
        return diff * (cardWidth * 0.4)
    }
    
    private func cardZIndex(for index: Int) -> Double {
        return Double(allVideos.count - abs(index - currentIndex))
    }
    
    private func cardOpacity(for index: Int) -> Double {
        let distance = abs(index - currentIndex)
        switch distance {
        case 0: return 1.0
        case 1: return 0.85
        default: return 0.5
        }
    }
    
    // MARK: - Page Navigation View
    
    private var pageNavigationView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Button(action: previousPage) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Prev")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(currentPage > 0 ? brandCyan : brandDark.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentPage > 0 ? brandCyan.opacity(0.1) : Color.clear)
                    )
                }
                .disabled(currentPage <= 0)
                
                VStack(spacing: 2) {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(brandDark)
                    
                    Text("\(childVideos.count) total replies")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(brandDark.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(brandCream.opacity(0.8))
                        .shadow(color: brandDark.opacity(0.1), radius: 2)
                )
                
                Button(action: nextPage) {
                    HStack(spacing: 6) {
                        Text("Next")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(currentPage < totalPages - 1 ? brandPurple : brandDark.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentPage < totalPages - 1 ? brandPurple.opacity(0.1) : Color.clear)
                    )
                }
                .disabled(currentPage >= totalPages - 1)
            }
            
            if totalPages <= 10 {
                HStack(spacing: 4) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        Circle()
                            .fill(page == currentPage ? brandPurple : brandDark.opacity(0.2))
                            .frame(width: page == currentPage ? 8 : 6, height: page == currentPage ? 8 : 6)
                            .onTapGesture {
                                jumpToPage(page)
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(brandCream.opacity(0.5))
                .shadow(color: brandDark.opacity(0.1), radius: 4)
        )
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(brandPurple)
            
            Text("Loading thread...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Failed to load")
                .font(.system(size: 18, weight: .bold))
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: loadThreadData) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(brandPurple))
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadThreadData() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let targetVideo = try await videoService.getVideo(id: threadID)
                let isReply = targetVideo.replyToVideoID != nil || targetVideo.conversationDepth > 0
                
                if isReply {
                    let stepchildren = try await videoService.getTimestampedReplies(videoID: threadID)
                    
                    await MainActor.run {
                        self.parentVideo = targetVideo
                        self.childVideos = stepchildren
                        self.isLoading = false
                        self.currentIndex = 0
                    }
                } else {
                    let threadData = try await videoService.getCompleteThread(threadID: threadID)
                    let directChildren = threadData.childVideos.filter { $0.conversationDepth == 1 }
                    
                    await MainActor.run {
                        self.parentVideo = threadData.parentVideo
                        self.childVideos = directChildren
                        self.isLoading = false
                        
                        if let targetID = targetVideoID {
                            if targetID == threadData.parentVideo.id {
                                currentPage = 0
                                currentIndex = 0
                            } else if let childIndex = directChildren.firstIndex(where: { $0.id == targetID }) {
                                let targetPage = childIndex / childrenPerPage
                                let indexOnPage = childIndex % childrenPerPage
                                currentPage = targetPage
                                currentIndex = indexOnPage + 1
                            } else {
                                Task { await navigateToStepchild(targetID: targetID) }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func openVideo(_ video: CoreVideoMetadata) {
        selectedVideo = video
        let isParent = video.id == parentVideo?.id
        
        if isParent {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showFullscreen = true
            }
        } else {
            Task {
                do {
                    // Get lanes (unique conversation partners) for this child
                    let lanes = try await laneService.getLanes(
                        forChildVideoID: video.id,
                        childCreatorID: video.creatorID
                    )
                    
                    // Convert lane first-replies to directReplies for nav bar
                    let laneFirstReplies = lanes.map { $0.firstReply }
                    
                    await MainActor.run {
                        self.carouselVideos = [video]
                        self.directReplies = laneFirstReplies
                        self.laneParticipantIDs = []  // No lane selected yet
                        self.currentLaneAnchorID = video.id
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.showCarousel = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.carouselVideos = [video]
                        self.directReplies = []
                        self.laneParticipantIDs = []
                        self.showCarousel = true
                    }
                }
            }
        }
    }
    
    private func loadConversation(with reply: CoreVideoMetadata) {
        guard let childVideo = selectedVideo else { return }
        
        Task {
            do {
                // Load full conversation chain between child creator and this responder
                let messages = try await laneService.loadLaneMessages(
                    childVideo: childVideo,
                    participant1: childVideo.creatorID,
                    participant2: reply.creatorID
                )
                
                await MainActor.run {
                    // Carousel: child video first, then the full back-and-forth chain
                    self.carouselVideos = [childVideo] + messages
                    // Track who's in this lane so overlay knows who can reply
                    self.laneParticipantIDs = [childVideo.creatorID, reply.creatorID]
                    self.currentLaneAnchorID = childVideo.id
                }
            } catch {
                print("❌ LANE: Failed to load conversation — \(error.localizedDescription)")
            }
        }
    }
    
    private func previousPage() {
        guard currentPage > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentPage -= 1
            currentIndex = 0
        }
    }
    
    private func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentPage += 1
            currentIndex = 0
        }
    }
    
    private func jumpToPage(_ page: Int) {
        guard page >= 0 && page < totalPages && page != currentPage else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentPage = page
            currentIndex = 0
        }
    }
    
    private func navigateToStepchild(targetID: String) async {
        do {
            let targetVideo = try await videoService.getVideo(id: targetID)
            var currentVideo = targetVideo
            
            // Walk up to find the depth-1 child anchor
            while currentVideo.conversationDepth > 1, let replyTo = currentVideo.replyToVideoID {
                currentVideo = try await videoService.getVideo(id: replyTo)
            }
            
            guard currentVideo.conversationDepth == 1 else { return }
            
            let childAnchor = currentVideo
            
            // Load full lane messages using lane service
            // Determine lane participants from the target video chain
            let lanes = try await laneService.getLanes(
                forChildVideoID: childAnchor.id,
                childCreatorID: childAnchor.creatorID
            )
            
            // Find which lane the target video belongs to
            let targetCreator = targetVideo.creatorID
            let matchingLane = lanes.first { $0.isParticipant(targetCreator) }
            
            if let lane = matchingLane {
                let messages = try await laneService.loadLaneMessages(
                    childVideo: childAnchor,
                    participant1: lane.childCreatorID,
                    participant2: lane.responderID
                )
                
                let conversationVideos = [childAnchor] + messages
                
                guard conversationVideos.contains(where: { $0.id == targetID }) else { return }
                
                await MainActor.run {
                    self.selectedVideo = targetVideo
                    self.carouselVideos = conversationVideos
                    self.laneParticipantIDs = lane.participantIDs
                    self.currentLaneAnchorID = childAnchor.id
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showCarousel = true
                    }
                }
            } else {
                // Fallback: just show the stepchildren flat
                let stepchildren = try await videoService.getTimestampedReplies(videoID: childAnchor.id)
                let conversationVideos = [childAnchor] + stepchildren
                
                await MainActor.run {
                    self.selectedVideo = targetVideo
                    self.carouselVideos = conversationVideos
                    self.laneParticipantIDs = []
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showCarousel = true
                    }
                }
            }
        } catch { }
    }
}

// MARK: - Thread Discovery Card (Thumbnail fills card + CreatorPill only)

private struct ThreadDiscoveryCard: View {
    let video: CoreVideoMetadata
    let isActive: Bool
    let isOrigin: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let brandCyan: Color
    let brandPurple: Color
    let isDragging: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail fills entire card
            thumbnailLayer
            
            // Gradient overlay at bottom for text readability
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.6), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Bottom overlay - just CreatorPill
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                
                // Title
                Text(video.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                
                // CreatorPill
                CreatorPill(
                    creator: video,
                    isThread: isOrigin,
                    colors: isOrigin ? [brandPurple, brandPink] : [brandCyan, brandPurple],
                    displayName: video.creatorName,
                    profileImageURL: nil,
                    onTap: { }  // Profile tap handled elsewhere
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: isActive
                            ? [brandCyan.opacity(0.6), brandPurple.opacity(0.6)]
                            : [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 2 : 1
                )
        )
        .shadow(
            color: isActive ? brandPurple.opacity(0.4) : Color.black.opacity(0.2),
            radius: isActive ? 20 : 10,
            y: 10
        )
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onTapGesture {
            if !isDragging && isActive {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    onTap()
                }
            }
        }
    }
    
    private var thumbnailLayer: some View {
        ZStack {
            // Gradient background fallback
            LinearGradient(
                colors: [brandPurple.opacity(0.4), brandCyan.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Thumbnail
            if !video.thumbnailURL.isEmpty, let url = URL(string: video.thumbnailURL) {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    } else {
                        // Loading state
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                // No thumbnail
                Image(systemName: "play.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    private let brandPink = Color(red: 0.95, green: 0.4, blue: 0.7)
}

// MARK: - Preview

#Preview {
    ThreadView(
        threadID: "sample",
        videoService: VideoService(),
        userService: UserService()
    )
}
