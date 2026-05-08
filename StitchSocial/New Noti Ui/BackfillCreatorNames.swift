//
//  BackfillCreatorNames.swift
//  StitchSocial
//
//  Created by James Garmon on 11/1/25.
//


import Foundation
import FirebaseFirestore
import FirebaseAuth

/// One-time backfill script to fix empty creatorName fields
class BackfillCreatorNames {
    
    static func run() async {
        let db = Firestore.firestore(database: "stitchfin")
        
        #if DEBUG
        print("🔍 Searching for videos with empty creatorName...")
        #endif
        
        do {
            let snapshot = try await db.collection("videos")
                .whereField("creatorName", isEqualTo: "")
                .getDocuments()
            
            #if DEBUG
            print("📊 Found \(snapshot.documents.count) videos to fix")
            #endif
            
            var fixedCount = 0
            
            for doc in snapshot.documents {
                let videoData = doc.data()
                guard let creatorID = videoData["creatorID"] as? String else {
                    #if DEBUG
                    print("⚠️ Skipping \(doc.documentID) - no creatorID")
                    #endif
                    continue
                }
                
                // Fetch username from users collection
                let userDoc = try await db.collection("users")
                    .document(creatorID)
                    .getDocument()
                
                guard userDoc.exists,
                      let userData = userDoc.data(),
                      let username = userData["username"] as? String else {
                    #if DEBUG
                    print("⚠️ No username found for user \(creatorID)")
                    #endif
                    continue
                }
                
                // Update video document
                try await doc.reference.updateData(["creatorName": username])
                fixedCount += 1
                #if DEBUG
                print("✅ Fixed: \(doc.documentID) → @\(username)")
                #endif
            }
            
            #if DEBUG
            print("🎉 Backfill complete! Fixed \(fixedCount) videos")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ Error: \(error.localizedDescription)")
            #endif
        }
    }
}