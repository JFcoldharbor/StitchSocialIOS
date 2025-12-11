//
//  QuickDraftClearer.swift
//  StitchSocial
//
//  Quick button to clear all drafts - add temporarily to any view
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Simple button to clear all collection drafts
/// Add this anywhere in your app temporarily to clear stuck drafts
struct QuickDraftClearerButton: View {
    @State private var isClearing = false
    @State private var message = ""
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task { await clearDrafts() }
            }) {
                HStack {
                    if isClearing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(isClearing ? "Clearing..." : "Clear All Drafts")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.red)
                .cornerRadius(10)
            }
            .disabled(isClearing)
            
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
    
    private func clearDrafts() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            message = "Not logged in"
            return
        }
        
        isClearing = true
        message = ""
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            print("🗑️ Found \(snapshot.documents.count) drafts to delete")
            
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
                print("  - Deleting: \(doc.documentID)")
            }
            
            try await batch.commit()
            
            message = "✅ Deleted \(snapshot.documents.count) drafts!"
            print("✅ All drafts deleted!")
            
        } catch {
            message = "❌ Error: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
        
        isClearing = false
    }
}

// MARK: - Usage Examples

/*
 
 OPTION 1: Add to SettingsView
 -----------------------------
 In your SettingsView body, add a section:
 
 Section("Debug") {
     QuickDraftClearerButton()
 }
 
 
 OPTION 2: Add to ProfileView temporarily
 ----------------------------------------
 In profileContent, add after the header:
 
 QuickDraftClearerButton()
     .padding()
 
 
 OPTION 3: Add to any view's overlay
 -----------------------------------
 .overlay(alignment: .bottom) {
     QuickDraftClearerButton()
         .padding(.bottom, 100)
 }
 
 
 OPTION 4: Call the function directly from .task
 -----------------------------------------------
 Add to any view:
 
 .task {
     await quickClearAllDrafts()
 }
 
 */

/// Standalone function to clear all drafts - call from anywhere
func quickClearAllDrafts() async {
    guard let userID = Auth.auth().currentUser?.uid else {
        print("❌ quickClearAllDrafts: Not logged in")
        return
    }
    
    let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    do {
        let snapshot = try await db.collection("collectionDrafts")
            .whereField("creatorID", isEqualTo: userID)
            .getDocuments()
        
        guard !snapshot.documents.isEmpty else {
            print("✅ No drafts to delete")
            return
        }
        
        print("🗑️ Deleting \(snapshot.documents.count) drafts...")
        
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        
        try await batch.commit()
        print("✅ All \(snapshot.documents.count) drafts deleted!")
        
    } catch {
        print("❌ Error clearing drafts: \(error)")
    }
}

// MARK: - Preview

#if DEBUG
struct QuickDraftClearerButton_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            QuickDraftClearerButton()
        }
    }
}
#endif
