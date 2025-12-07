//
//  SearchableTextBackfill.swift
//  StitchSocial
//
//  Created by James Garmon on 12/6/25.
//


//
//  SearchableTextBackfill.swift
//  StitchSocial
//
//  One-time migration service to populate searchableText field for all existing users
//  Run this once to enable efficient case-insensitive user search
//
//  Usage: Call SearchableTextBackfill.shared.backfillAllUsers() from app startup or admin panel
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Service to backfill searchableText field for existing users
@MainActor
class SearchableTextBackfill: ObservableObject {
    
    static let shared = SearchableTextBackfill()
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    @Published var isRunning = false
    @Published var progress: Int = 0
    @Published var total: Int = 0
    @Published var lastError: String?
    @Published var completed = false
    
    private init() {}
    
    // MARK: - Main Backfill Function
    
    /// Backfill searchableText for ALL users in database
    /// Safe to run multiple times - only updates users missing the field
    func backfillAllUsers() async {
        guard !isRunning else {
            print("⚠️ BACKFILL: Already running")
            return
        }
        
        isRunning = true
        progress = 0
        total = 0
        lastError = nil
        completed = false
        
        print("🔄 BACKFILL: Starting searchableText backfill for all users...")
        
        do {
            // Get all users
            let snapshot = try await db.collection(FirebaseSchema.Collections.users)
                .getDocuments()
            
            total = snapshot.documents.count
            print("🔄 BACKFILL: Found \(total) users to process")
            
            var updatedCount = 0
            var skippedCount = 0
            var errorCount = 0
            
            // Process in batches of 50
            let batchSize = 50
            var batch = db.batch()
            var batchCount = 0
            
            for document in snapshot.documents {
                let data = document.data()
                let userID = document.documentID
                
                // Check if searchableText already exists and is valid
                if let existingSearchable = data[FirebaseSchema.UserDocument.searchableText] as? String,
                   !existingSearchable.isEmpty {
                    skippedCount += 1
                    progress += 1
                    continue
                }
                
                // Get username and displayName
                let username = data[FirebaseSchema.UserDocument.username] as? String ?? ""
                let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? ""
                
                // Skip if both are empty
                guard !username.isEmpty || !displayName.isEmpty else {
                    print("⚠️ BACKFILL: Skipping user \(userID) - no username or displayName")
                    skippedCount += 1
                    progress += 1
                    continue
                }
                
                // Generate searchableText
                let searchableText = FirebaseSchema.UserDocument.generateSearchableText(
                    username: username,
                    displayName: displayName
                )
                
                // Add to batch
                let userRef = db.collection(FirebaseSchema.Collections.users).document(userID)
                batch.updateData([
                    FirebaseSchema.UserDocument.searchableText: searchableText
                ], forDocument: userRef)
                
                batchCount += 1
                updatedCount += 1
                
                // Commit batch when full
                if batchCount >= batchSize {
                    do {
                        try await batch.commit()
                        print("✅ BACKFILL: Committed batch of \(batchCount) users")
                        batch = db.batch()
                        batchCount = 0
                    } catch {
                        print("❌ BACKFILL: Batch commit failed: \(error)")
                        errorCount += batchCount
                        batch = db.batch()
                        batchCount = 0
                    }
                }
                
                progress += 1
            }
            
            // Commit remaining batch
            if batchCount > 0 {
                do {
                    try await batch.commit()
                    print("✅ BACKFILL: Committed final batch of \(batchCount) users")
                } catch {
                    print("❌ BACKFILL: Final batch commit failed: \(error)")
                    errorCount += batchCount
                }
            }
            
            completed = true
            isRunning = false
            
            print("✅ BACKFILL COMPLETE:")
            print("   - Total users: \(total)")
            print("   - Updated: \(updatedCount)")
            print("   - Skipped (already had searchableText): \(skippedCount)")
            print("   - Errors: \(errorCount)")
            
        } catch {
            lastError = error.localizedDescription
            isRunning = false
            print("❌ BACKFILL: Failed to fetch users: \(error)")
        }
    }
    
    // MARK: - Single User Update
    
    /// Update searchableText for a single user
    func updateSingleUser(userID: String) async throws {
        let docRef = db.collection(FirebaseSchema.Collections.users).document(userID)
        let document = try await docRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "SearchableTextBackfill", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "User not found"
            ])
        }
        
        let username = data[FirebaseSchema.UserDocument.username] as? String ?? ""
        let displayName = data[FirebaseSchema.UserDocument.displayName] as? String ?? ""
        
        let searchableText = FirebaseSchema.UserDocument.generateSearchableText(
            username: username,
            displayName: displayName
        )
        
        try await docRef.updateData([
            FirebaseSchema.UserDocument.searchableText: searchableText
        ])
        
        print("✅ BACKFILL: Updated searchableText for user \(userID): '\(searchableText)'")
    }
    
    // MARK: - Validation
    
    /// Check how many users are missing searchableText
    func checkMissingSearchableText() async -> (total: Int, missing: Int) {
        do {
            let snapshot = try await db.collection(FirebaseSchema.Collections.users)
                .getDocuments()
            
            var missingCount = 0
            for document in snapshot.documents {
                let data = document.data()
                if let searchable = data[FirebaseSchema.UserDocument.searchableText] as? String,
                   !searchable.isEmpty {
                    continue
                }
                missingCount += 1
            }
            
            print("📊 BACKFILL CHECK: \(missingCount)/\(snapshot.documents.count) users missing searchableText")
            return (snapshot.documents.count, missingCount)
            
        } catch {
            print("❌ BACKFILL CHECK: Failed: \(error)")
            return (0, 0)
        }
    }
}

// MARK: - App Startup Integration

extension SearchableTextBackfill {
    
    /// Call this from app startup to auto-backfill if needed
    /// Only runs if more than 10% of users are missing searchableText
    func autoBackfillIfNeeded() async {
        let (total, missing) = await checkMissingSearchableText()
        
        guard total > 0 else { return }
        
        let missingPercentage = Double(missing) / Double(total)
        
        if missingPercentage > 0.1 {
            print("🔄 AUTO-BACKFILL: \(Int(missingPercentage * 100))% of users missing searchableText, starting backfill...")
            await backfillAllUsers()
        } else if missing > 0 {
            print("ℹ️ AUTO-BACKFILL: Only \(missing) users missing searchableText, skipping full backfill")
        } else {
            print("✅ AUTO-BACKFILL: All users have searchableText")
        }
    }
}