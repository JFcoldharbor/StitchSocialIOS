//
//  CollectionsListView.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionsListView.swift
//  StitchSocial
//
//  Layer 6: Views - Collections Discovery & Browse
//  Dependencies: CollectionRowView, CollectionCoordinator, CollectionService
//  Features: Discovery feed, search, filtering, pull-to-refresh, infinite scroll
//  CREATED: Phase 6 - Collections feature Full Screens
//

import SwiftUI

/// Browse view for discovering and exploring collections
/// Shows trending, recent, and followed creator collections
struct CollectionsListView: View {
    
    // MARK: - Properties
    
    @StateObject private var viewModel: CollectionsListViewModel
    @ObservedObject var coordinator: CollectionCoordinator
    
    // MARK: - Local State
    
    @State private var selectedFilter: CollectionFilter = .discover
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    
    // MARK: - Initialization
    
    init(coordinator: CollectionCoordinator, userID: String) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: CollectionsListViewModel(userID: userID))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.collections.isEmpty {
                    loadingView
                } else if viewModel.collections.isEmpty {
                    emptyStateView
                } else {
                    collectionsList
                }
            }
            .navigationTitle("Collections")
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search collections")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    createButton
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onChange(of: searchText) { _, newValue in
                viewModel.search(query: newValue)
            }
            .onChange(of: selectedFilter) { _, newFilter in
                Task {
                    await viewModel.loadCollections(filter: newFilter)
                }
            }
            .task {
                await viewModel.loadCollections(filter: selectedFilter)
            }
        }
    }
    
    // MARK: - Collections List
    
    private var collectionsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Filter Pills
                filterPills
                    .padding(.horizontal)
                
                // Collections
                ForEach(viewModel.filteredCollections) { collection in
                    CollectionRowView(
                        collection: collection,
                        style: .card,
                        onTap: {
                            coordinator.playCollection(collection)
                        },
                        onCreatorTap: {
                            // Navigate to creator profile
                        }
                    )
                    .padding(.horizontal)
                }
                
                // Load More
                if viewModel.hasMore {
                    loadMoreButton
                }
                
                // Bottom padding
                Spacer(minLength: 80)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Filter Pills
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CollectionFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.displayName,
                        icon: filter.iconName,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading collections...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            
            Text(emptyStateTitle)
                .font(.headline)
            
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if selectedFilter == .myCollections || selectedFilter == .drafts {
                Button {
                    coordinator.startNewCollection()
                } label: {
                    Label("Create Collection", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var emptyStateIcon: String {
        switch selectedFilter {
        case .discover: return "magnifyingglass"
        case .trending: return "flame"
        case .following: return "person.2"
        case .myCollections: return "square.stack.3d.up"
        case .drafts: return "doc.badge.ellipsis"
        }
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .discover: return "No Collections Found"
        case .trending: return "No Trending Collections"
        case .following: return "No Collections from Followed"
        case .myCollections: return "No Collections Yet"
        case .drafts: return "No Drafts"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .discover:
            return "Check back later for new collections"
        case .trending:
            return "Trending collections will appear here"
        case .following:
            return "Collections from people you follow will appear here"
        case .myCollections:
            return "Create your first collection to share multi-part content"
        case .drafts:
            return "Your draft collections will appear here"
        }
    }
    
    // MARK: - Load More Button
    
    private var loadMoreButton: some View {
        Button {
            Task {
                await viewModel.loadMore()
            }
        } label: {
            if viewModel.isLoadingMore {
                ProgressView()
                    .padding()
            } else {
                Text("Load More")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                    .padding()
            }
        }
    }
    
    // MARK: - Create Button
    
    private var createButton: some View {
        Button {
            coordinator.startNewCollection()
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
    }
}

// MARK: - Collection Filter

enum CollectionFilter: String, CaseIterable {
    case discover = "discover"
    case trending = "trending"
    case following = "following"
    case myCollections = "my_collections"
    case drafts = "drafts"
    
    var displayName: String {
        switch self {
        case .discover: return "Discover"
        case .trending: return "Trending"
        case .following: return "Following"
        case .myCollections: return "My Collections"
        case .drafts: return "Drafts"
        }
    }
    
    var iconName: String {
        switch self {
        case .discover: return "sparkles"
        case .trending: return "flame"
        case .following: return "person.2"
        case .myCollections: return "square.stack.3d.up"
        case .drafts: return "doc.badge.ellipsis"
        }
    }
}

// MARK: - Collections List ViewModel

@MainActor
class CollectionsListViewModel: ObservableObject {
    
    // MARK: - Properties
    
    private let collectionService: CollectionService
    private let userID: String
    
    // MARK: - Published State
    
    @Published var collections: [VideoCollection] = []
    @Published var drafts: [CollectionDraft] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMore: Bool = false
    @Published var errorMessage: String?
    @Published var searchQuery: String = ""
    
    // MARK: - Private State
    
    private var currentFilter: CollectionFilter = .discover
    
    // MARK: - Computed Properties
    
    var filteredCollections: [VideoCollection] {
        if searchQuery.isEmpty {
            return collections
        }
        
        return collections.filter { collection in
            collection.title.localizedCaseInsensitiveContains(searchQuery) ||
            collection.creatorName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    // MARK: - Initialization
    
    init(userID: String, collectionService: CollectionService) {
        self.userID = userID
        self.collectionService = collectionService
    }
    
    convenience init(userID: String) {
        self.init(userID: userID, collectionService: CollectionService())
    }
    
    // MARK: - Loading
    
    func loadCollections(filter: CollectionFilter) async {
        currentFilter = filter
        isLoading = true
        
        do {
            switch filter {
            case .discover:
                collections = try await collectionService.getDiscoveryCollections(limit: 20)
                
            case .trending:
                // Would sort by engagement metrics
                collections = try await collectionService.getDiscoveryCollections(limit: 20)
                
            case .following:
                // Would filter by followed creators
                collections = try await collectionService.getDiscoveryCollections(limit: 20)
                
            case .myCollections:
                collections = try await collectionService.getUserCollections(userID: userID)
                
            case .drafts:
                drafts = try await collectionService.loadUserDrafts(creatorID: userID)
                collections = [] // Drafts shown separately
            }
            
            hasMore = collections.count >= 20
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        
        isLoadingMore = true
        
        // Would implement pagination here
        
        isLoadingMore = false
    }
    
    func refresh() async {
        await loadCollections(filter: currentFilter)
    }
    
    func search(query: String) {
        searchQuery = query
    }
}

