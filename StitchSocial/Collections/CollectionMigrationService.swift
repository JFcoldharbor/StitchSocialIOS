//
//  CollectionMigrationService.swift
//  StitchSocial
//
//  Created by James Garmon on 4/2/26.
//


//
//  CollectionMigrationService.swift
//  StitchSocial
//
//  Layer 4: Services - Auto-wrap orphan collections into shows
//  Runs on profile load. Detects collections with no showId,
//  creates a show + season for each, updates the collection doc.
//  Idempotent — skips collections that already have a showId.
//
//  CACHING: Runs once per profile load. Writes are batched.
//  After migration, ShowService cache is invalidated so fresh data loads.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class CollectionMigrationService {
    
    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    
    /// Check and migrate orphan collections for a user.
    /// Call this on profile load before displaying collections.
    /// Returns number of collections migrated.
    func migrateOrphanCollections(userID: String, creatorName: String) async -> Int {
        do {
            // Find collections with no showId or empty showId
            let snapshot = try await db.collection("videoCollections")
                .whereField("creatorID", isEqualTo: userID)
                .whereField("status", isEqualTo: "published")
                .getDocuments()
            
            let orphans = snapshot.documents.filter { doc in
                let data = doc.data()
                let showId = data["showId"] as? String ?? ""
                return showId.isEmpty
            }
            
            guard !orphans.isEmpty else {
                print("🔄 MIGRATION: No orphan collections found for \(userID)")
                return 0
            }
            
            print("🔄 MIGRATION: Found \(orphans.count) orphan collections to wrap into shows")
            
            var migratedCount = 0
            
            for doc in orphans {
                let data = doc.data()
                let collectionId = doc.documentID
                let title = data["title"] as? String ?? "Untitled"
                let contentTypeRaw = data["contentType"] as? String ?? "standard"
                
                // Create a show for this collection
                let showId = UUID().uuidString
                let seasonId = UUID().uuidString
                
                // Determine genre from content type
                let genre = genreFromContentType(contentTypeRaw)
                
                let batch = db.batch()
                
                // 1. Create show doc
                let showRef = db.collection("shows").document(showId)
                batch.setData([
                    "id": showId,
                    "title": title,
                    "description": data["description"] as? String ?? "",
                    "creatorID": userID,
                    "creatorName": creatorName,
                    "format": "vertical",
                    "genre": genre,
                    "contentType": contentTypeRaw,
                    "tags": [] as [String],
                    "coverImageURL": data["coverImageURL"] as? String ?? "",
                    "thumbnailURL": "",
                    "status": "published",
                    "isFeatured": false,
                    "seasonCount": 1,
                    "totalEpisodes": 1,
                    "totalViews": data["totalViews"] as? Int ?? 0,
                    "totalHypes": data["totalHypes"] as? Int ?? 0,
                    "totalCools": data["totalCools"] as? Int ?? 0,
                    "createdAt": data["createdAt"] ?? Timestamp(),
                    "updatedAt": Timestamp(),
                ] as [String: Any], forDocument: showRef)
                
                // 2. Create season doc
                let seasonRef = db.collection("shows").document(showId)
                    .collection("seasons").document(seasonId)
                batch.setData([
                    "id": seasonId,
                    "showId": showId,
                    "number": 1,
                    "title": "Season 1",
                    "description": "",
                    "coverImageURL": "",
                    "status": "published",
                    "episodeCount": 1,
                    "totalViews": 0,
                    "totalHypes": 0,
                    "totalCools": 0,
                    "createdAt": Timestamp(),
                    "updatedAt": Timestamp(),
                ] as [String: Any], forDocument: seasonRef)
                
                // 3. Update the collection doc with showId/seasonId
                let collectionRef = db.collection("videoCollections").document(collectionId)
                batch.updateData([
                    "showId": showId,
                    "seasonId": seasonId,
                    "episodeNumber": 1,
                    "format": "vertical",
                ], forDocument: collectionRef)
                
                try await batch.commit()
                migratedCount += 1
                
                print("🔄 MIGRATION: Wrapped '\(title)' → show \(showId)")
            }
            
            print("🔄 MIGRATION: Migrated \(migratedCount) orphan collections into shows")
            return migratedCount
            
        } catch {
            print("❌ MIGRATION: Failed: \(error)")
            return 0
        }
    }
    
    /// Map old contentType strings to new genre values
    private func genreFromContentType(_ contentType: String) -> String {
        switch contentType {
        case "podcast": return "podcast"
        case "shortFilm": return "shortFilm"
        case "documentary": return "documentary"
        case "interview": return "interview"
        case "series": return "series"
        case "tutorial": return "tutorial"
        default: return "other"
        }
    }
}