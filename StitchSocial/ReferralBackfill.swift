//
//  ReferralBackfill.swift
//  StitchSocial
//
//  Created by James Garmon on 3/13/26.
//


// ReferralBackfill.swift
// StitchSocial
//
// ONE-TIME backfill script — run once from any view's .task {} then remove.
// Updates referralCount on ambassadors and invitedBy on referred users.
//
// Usage: Add to any view temporarily:
//   .task { await ReferralBackfill.run() }
//
// Then DELETE this file after confirming Firestore updated.

import Foundation
import FirebaseFirestore

enum ReferralBackfill {
    
    private static let db = FirebaseConfig.firestore
    
    struct AmbassadorBackfill {
        let ambassadorID: String
        let referralIDs: [String]
    }
    
    static let backfills: [AmbassadorBackfill] = [
        // User 1: cJsx...MDS2 — 3 referrals
        AmbassadorBackfill(
            ambassadorID: "cJsxoB3DuWS64tbuqt4xtoeRMDS2",
            referralIDs: [
                "z7yase9yKofsT7JB6TrHljz2PI83",
                "XJsrLvkG4uX5Q8IUqSr7Ns00RKo2",
                "tl3od2pmlWaNdrHEEIsdgcTadw72"
            ]
        ),
        // User 2: AZUAs...Zn2 — 15 referrals
        AmbassadorBackfill(
            ambassadorID: "AZUAsfkobQWSqXzgTR1UM2uogZn2",
            referralIDs: [
                "wJAP5I5zvcWQbFph0P14A4iw2fV2",
                "0MN9BMMEpuTfCZ3k1ftQoaohpEI3",
                "PW3EISJnqNSOCI8xUQsrcWOqOXJ3",
                "cva0VNOawVWlNZiSOOWnFLcjR5p2",
                "Qundrl9Wrqbj0PJTkuaVYgfeOot1",
                "gYzdkhqoQrhaE9gcTdXH6bWnf2f2",
                "gEcrkKsah3N4CqD9N2ZJ8xbawvK2",
                "3Avu8LmaQPZD1L9oIy69RizAPXg1",
                "WfZiYzVTXjevA0KVfUORYWZWLRI2",
                "svw5IfWE6adYFlOOmt4I03CMcU23",
                "xNO5adKOhAOl80iOOy4ZiVuq4Jk2",
                "946JbJLil3YhfuQj956pm4lmzg33",
                "h1gIdu6sCySAGEfFiJ4Pffyi94A2",
                "rxn9pNi9tVbAxs7w8b6HxnaUA533",
                "rv7YT00qUsV7bz7wX3hjJ5kaFf12"
            ]
        )
    ]
    
    static func run() async {
        print("🔧 BACKFILL: Starting referral backfill...")
        
        for entry in backfills {
            do {
                let batch = db.batch()
                let count = entry.referralIDs.count
                
                // Update ambassador's referralCount
                let ambassadorRef = db.collection("users").document(entry.ambassadorID)
                batch.updateData([
                    "referralCount": count,
                    "updatedAt": Timestamp()
                ], forDocument: ambassadorRef)
                
                // Set invitedBy on each referred user
                for referralID in entry.referralIDs {
                    let userRef = db.collection("users").document(referralID)
                    batch.updateData([
                        "invitedBy": entry.ambassadorID,
                        "updatedAt": Timestamp()
                    ], forDocument: userRef)
                }
                
                try await batch.commit()
                print("✅ BACKFILL: \(entry.ambassadorID) — \(count) referrals written")
                
                // Check if this hits their referral goal
                let doc = try await ambassadorRef.getDocument()
                if let data = doc.data(),
                   let goal = data["referralGoal"] as? Int,
                   count >= goal,
                   data["customSubSharePermanent"] as? Bool != true {
                    try await ambassadorRef.updateData([
                        "customSubSharePermanent": true
                    ])
                    print("🏆 BACKFILL: \(entry.ambassadorID) hit goal \(count)/\(goal) — 80/20 locked permanent!")
                }
                
            } catch {
                print("❌ BACKFILL: Failed for \(entry.ambassadorID) — \(error.localizedDescription)")
            }
        }
        
        print("🔧 BACKFILL: Complete!")
    }
}