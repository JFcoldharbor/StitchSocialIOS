//
//  ShowListView.swift
//  StitchSocial
//
//  Layer 6: Views - Show List (Creator's Shows)
//  Dependencies: ShowService, Show, Season
//  Entry point for Show → Season → Episode → EpisodeEditor navigation
//
//  CACHING: ShowService caches shows for 30 min.
//  Pull-to-refresh invalidates and re-fetches.
//

import SwiftUI
import FirebaseAuth

struct ShowListView: View {
    
    let userID: String
    let username: String
    let onDismiss: () -> Void
    
    @StateObject private var showService = ShowService()
    @State private var shows: [Show] = []
    @State private var isLoading = true
    @State private var selectedShow: Show?
    @State private var showingShowEditor = false
    @State private var showingNewShow = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading && shows.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else if shows.isEmpty {
                    emptyState
                } else {
                    showsList
                }
            }
            .navigationTitle("My Shows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDismiss() }
                        .foregroundColor(.cyan)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewShow = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.pink)
                    }
                }
            }
            .task { await loadShows() }
            .refreshable { await loadShows() }
            .sheet(isPresented: $showingNewShow) {
                NavigationStack {
                    ShowEditorView(
                        show: Show.newDraft(creatorID: userID, creatorName: username),
                        isNew: true,
                        onSave: { savedShow in
                            shows.insert(savedShow, at: 0)
                            showingNewShow = false
                        },
                        onDismiss: { showingNewShow = false }
                    )
                }
                .preferredColorScheme(.dark)
            }
            .navigationDestination(item: $selectedShow) { show in
                ShowEditorView(
                    show: show,
                    isNew: false,
                    onSave: { updatedShow in
                        if let idx = shows.firstIndex(where: { $0.id == updatedShow.id }) {
                            shows[idx] = updatedShow
                        }
                    },
                    onDismiss: { selectedShow = nil }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text("No Shows Yet")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text("Create your first show to start adding seasons and episodes.")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showingNewShow = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Create Show")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Shows List
    
    private var showsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(shows) { show in
                    ShowRowView(show: show) {
                        selectedShow = show
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Load
    
    private func loadShows() async {
        isLoading = true
        do {
            shows = try await showService.getCreatorShows(creatorID: userID)
        } catch {
            print("❌ SHOW LIST: Failed to load: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Show Row

struct ShowRowView: View {
    let show: Show
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Cover thumbnail
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 60, height: 80)
                    .overlay(
                        Image(systemName: show.contentType.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.5))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(show.title.isEmpty ? "Untitled Show" : show.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("\(show.seasonCount) seasons · \(show.totalEpisodes) episodes")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 6) {
                        // Status pill
                        Text(show.status.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(show.status))
                            .cornerRadius(4)
                        
                        // Format pill
                        Text(show.format.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                        
                        // Genre
                        Text(show.genre.displayName)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func statusColor(_ status: ShowStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .published: return .green
        case .paused: return .orange
        case .completed: return .blue
        case .removed: return .red
        }
    }
}
