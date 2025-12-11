//
//  DraftCleanupUtility.swift
//  StitchSocial
//
//  Utility to clear orphaned/stuck collection drafts
//  Add to Settings or call once to clear drafts that aren't showing in UI
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Utility class to manage and cleanup collection drafts
@MainActor
class DraftCleanupUtility: ObservableObject {
    
    @Published var isLoading = false
    @Published var draftsFound: [DraftInfo] = []
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    struct DraftInfo: Identifiable {
        let id: String
        let title: String?
        let createdAt: Date?
        let segmentCount: Int
    }
    
    /// Fetch all drafts for current user
    func fetchDrafts() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "Not logged in"
            return
        }
        
        isLoading = true
        statusMessage = "Loading drafts..."
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            draftsFound = snapshot.documents.compactMap { doc -> DraftInfo? in
                let data = doc.data()
                let title = data["title"] as? String
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                let segments = data["segments"] as? [[String: Any]] ?? []
                
                return DraftInfo(
                    id: doc.documentID,
                    title: title,
                    createdAt: createdAt,
                    segmentCount: segments.count
                )
            }
            
            statusMessage = "Found \(draftsFound.count) drafts"
            print("🧹 CLEANUP: Found \(draftsFound.count) drafts for user \(userID)")
            
        } catch {
            errorMessage = "Failed to fetch drafts: \(error.localizedDescription)"
            print("❌ CLEANUP: Error fetching drafts: \(error)")
        }
        
        isLoading = false
    }
    
    /// Delete a single draft
    func deleteDraft(_ draft: DraftInfo) async {
        isLoading = true
        
        do {
            try await db.collection("collectionDrafts").document(draft.id).delete()
            draftsFound.removeAll { $0.id == draft.id }
            statusMessage = "Deleted draft: \(draft.id.prefix(8))..."
            print("🗑️ CLEANUP: Deleted draft \(draft.id)")
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Delete ALL drafts for current user
    func deleteAllDrafts() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            errorMessage = "Not logged in"
            return
        }
        
        isLoading = true
        statusMessage = "Deleting all drafts..."
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            
            try await batch.commit()
            
            draftsFound.removeAll()
            statusMessage = "Deleted \(snapshot.documents.count) drafts"
            print("🗑️ CLEANUP: Deleted all \(snapshot.documents.count) drafts for user \(userID)")
            
        } catch {
            errorMessage = "Failed to delete all: \(error.localizedDescription)"
            print("❌ CLEANUP: Error deleting all drafts: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Draft Cleanup View (Add to Settings)

struct DraftCleanupView: View {
    @StateObject private var utility = DraftCleanupUtility()
    @State private var showDeleteAllConfirm = false
    
    var body: some View {
        List {
            // Status Section
            Section {
                if utility.isLoading {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(utility.statusMessage ?? "Loading...")
                            .foregroundColor(.gray)
                    }
                } else if let status = utility.statusMessage {
                    Text(status)
                        .foregroundColor(.green)
                }
                
                if let error = utility.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: {
                    Task { await utility.fetchDrafts() }
                }) {
                    Label("Scan for Drafts", systemImage: "magnifyingglass")
                }
                .disabled(utility.isLoading)
                
                Button(role: .destructive, action: {
                    showDeleteAllConfirm = true
                }) {
                    Label("Delete All Drafts", systemImage: "trash.fill")
                }
                .disabled(utility.isLoading || utility.draftsFound.isEmpty)
            }
            
            // Drafts List Section
            if !utility.draftsFound.isEmpty {
                Section("Found Drafts (\(utility.draftsFound.count))") {
                    ForEach(utility.draftsFound) { draft in
                        DraftRow(draft: draft) {
                            Task { await utility.deleteDraft(draft) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Draft Cleanup")
        .alert("Delete All Drafts?", isPresented: $showDeleteAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                Task { await utility.deleteAllDrafts() }
            }
        } message: {
            Text("This will permanently delete all \(utility.draftsFound.count) collection drafts. This cannot be undone.")
        }
        .task {
            await utility.fetchDrafts()
        }
    }
}

struct DraftRow: View {
    let draft: DraftCleanupUtility.DraftInfo
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title ?? "Untitled Draft")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Text(draft.id.prefix(12) + "...")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let date = draft.createdAt {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text("\(draft.segmentCount) segments")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Clear Function (Call from anywhere)

/// Quick function to clear all drafts - call this once to fix the issue
func clearAllCollectionDrafts() async {
    guard let userID = Auth.auth().currentUser?.uid else {
        print("❌ Not logged in")
        return
    }
    
    let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    do {
        let snapshot = try await db.collection("collectionDrafts")
            .whereField("creatorID", isEqualTo: userID)
            .getDocuments()
        
        print("🧹 Found \(snapshot.documents.count) drafts to delete")
        
        let batch = db.batch()
        for doc in snapshot.documents {
            print("  - Deleting: \(doc.documentID)")
            batch.deleteDocument(doc.reference)
        }
        
        try await batch.commit()
        print("✅ All drafts deleted successfully!")
        
    } catch {
        print("❌ Error clearing drafts: \(error)")
    }
}

// MARK: - Settings Integration

/// Add this to your SettingsView
struct SettingsDraftCleanupRow: View {
    var body: some View {
        NavigationLink(destination: DraftCleanupView()) {
            Label("Collection Drafts", systemImage: "doc.text.magnifyingglass")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct DraftCleanupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DraftCleanupView()
        }
        .preferredColorScheme(.dark)
    }
}
#endif
