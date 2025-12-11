//
//  CollectionDraftDiagnostic.swift
//  StitchSocial
//
//  Created by James Garmon on 12/10/25.
//


//
//  CollectionDraftDiagnostic.swift
//  StitchSocial
//
//  Diagnostic tool to find why drafts aren't decoding
//  Add to Settings temporarily to diagnose the issue
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CollectionDraftDiagnostic: View {
    @State private var diagnosticResults: [DiagnosticResult] = []
    @State private var isLoading = false
    @State private var summary = ""
    
    struct DiagnosticResult: Identifiable {
        let id: String
        let docID: String
        let hasCreatorID: Bool
        let hasVisibility: Bool
        let visibilityValue: String?
        let visibilityValid: Bool
        let wouldDecode: Bool
        let failureReason: String?
    }
    
    var body: some View {
        List {
            Section("Summary") {
                if isLoading {
                    ProgressView("Analyzing drafts...")
                } else {
                    Text(summary)
                        .font(.subheadline)
                }
            }
            
            Section("Actions") {
                Button("Run Diagnostic") {
                    Task { await runDiagnostic() }
                }
                .disabled(isLoading)
                
                Button("Fix All Drafts (Add Missing Visibility)") {
                    Task { await fixAllDrafts() }
                }
                .disabled(isLoading)
                .foregroundColor(.orange)
                
                Button("Delete All Drafts") {
                    Task { await deleteAllDrafts() }
                }
                .disabled(isLoading)
                .foregroundColor(.red)
            }
            
            Section("Draft Analysis (\(diagnosticResults.count))") {
                ForEach(diagnosticResults) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(result.docID.prefix(16) + "...")
                                .font(.caption.monospaced())
                            Spacer()
                            Text(result.wouldDecode ? "✅ OK" : "❌ FAIL")
                                .font(.caption.bold())
                                .foregroundColor(result.wouldDecode ? .green : .red)
                        }
                        
                        Group {
                            checkRow("creatorID", result.hasCreatorID)
                            checkRow("visibility field exists", result.hasVisibility)
                            
                            if let value = result.visibilityValue {
                                HStack {
                                    Text("  visibility value:")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text("\"\(value)\"")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(result.visibilityValid ? .green : .red)
                                }
                            }
                            
                            checkRow("visibility valid enum", result.visibilityValid)
                        }
                        
                        if let reason = result.failureReason {
                            Text("Failure: \(reason)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Draft Diagnostic")
    }
    
    private func checkRow(_ label: String, _ passed: Bool) -> some View {
        HStack {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
                .font(.caption)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
    
    private func runDiagnostic() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            summary = "Not logged in"
            return
        }
        
        isLoading = true
        diagnosticResults = []
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            var passCount = 0
            var failCount = 0
            
            for doc in snapshot.documents {
                let data = doc.data()
                
                let hasCreatorID = data["creatorID"] as? String != nil
                let hasVisibility = data["visibility"] != nil
                let visibilityValue = data["visibility"] as? String
                
                // Check if visibility value is valid
                var visibilityValid = false
                if let vis = visibilityValue {
                    visibilityValid = CollectionVisibility(rawValue: vis) != nil
                }
                
                // Determine if it would decode
                let wouldDecode = hasCreatorID && hasVisibility && visibilityValid
                
                // Determine failure reason
                var failureReason: String? = nil
                if !wouldDecode {
                    if !hasCreatorID {
                        failureReason = "Missing creatorID"
                    } else if !hasVisibility {
                        failureReason = "Missing visibility field"
                    } else if !visibilityValid {
                        failureReason = "Invalid visibility value: '\(visibilityValue ?? "nil")' - expected 'public', 'followers', or 'private'"
                    }
                }
                
                if wouldDecode {
                    passCount += 1
                } else {
                    failCount += 1
                }
                
                diagnosticResults.append(DiagnosticResult(
                    id: doc.documentID,
                    docID: doc.documentID,
                    hasCreatorID: hasCreatorID,
                    hasVisibility: hasVisibility,
                    visibilityValue: visibilityValue,
                    visibilityValid: visibilityValid,
                    wouldDecode: wouldDecode,
                    failureReason: failureReason
                ))
            }
            
            summary = """
            Found \(snapshot.documents.count) drafts in Firebase
            ✅ Would decode: \(passCount)
            ❌ Would fail: \(failCount)
            
            Expected visibility values: "public", "followers", "private"
            """
            
        } catch {
            summary = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func fixAllDrafts() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            summary = "Not logged in"
            return
        }
        
        isLoading = true
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            var fixedCount = 0
            
            for doc in snapshot.documents {
                let data = doc.data()
                let hasVisibility = data["visibility"] as? String != nil
                let visibilityValue = data["visibility"] as? String
                let isValid = visibilityValue.flatMap { CollectionVisibility(rawValue: $0) } != nil
                
                // Fix if missing or invalid
                if !hasVisibility || !isValid {
                    try await db.collection("collectionDrafts")
                        .document(doc.documentID)
                        .updateData(["visibility": "public"])
                    fixedCount += 1
                    print("🔧 Fixed draft \(doc.documentID): set visibility to 'public'")
                }
            }
            
            summary = "Fixed \(fixedCount) drafts by setting visibility to 'public'"
            
            // Re-run diagnostic
            await runDiagnostic()
            
        } catch {
            summary = "Error fixing drafts: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func deleteAllDrafts() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            summary = "Not logged in"
            return
        }
        
        isLoading = true
        
        let db = Firestore.firestore(database: Config.Firebase.databaseName)
        
        do {
            let snapshot = try await db.collection("collectionDrafts")
                .whereField("creatorID", isEqualTo: userID)
                .getDocuments()
            
            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            
            try await batch.commit()
            
            summary = "Deleted \(snapshot.documents.count) drafts"
            diagnosticResults = []
            
        } catch {
            summary = "Error deleting drafts: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Add to Settings

struct SettingsDraftDiagnosticRow: View {
    var body: some View {
        NavigationLink(destination: CollectionDraftDiagnostic()) {
            Label("Draft Diagnostic", systemImage: "stethoscope")
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CollectionDraftDiagnostic_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CollectionDraftDiagnostic()
        }
    }
}
#endif
