//
//  FilterCategory.swift
//  StitchSocial
//
//  Created by James Garmon on 3/21/26.
//


//
//  FilterManifest.swift
//  StitchSocial
//
//  Shared filter schema — same structure mirrored in FilterManifest.kt (Android)
//  Firestore collection: "filters"
//  Firebase Storage: "filter_assets/{filterID}/"
//
//  CACHING: Add to optimization file
//  - FilterManifest list cached 30min TTL (slow-changing)
//  - Asset URLs cached after first fetch — never re-read per session
//  - Downloaded asset bundles cached to disk (URLCache / FileManager)
//
//  BATCHING: All filter docs fetched in ONE query on app launch
//  — never fetch individual filter docs
//
//  Firestore document structure:
//  filters/{filterID} {
//    id:           String
//    name:         String
//    category:     String  (color | face | background | world)
//    type:         String  (cifilter | arkit | mlkit | segmentation)
//    tier:         String  (free | subscriber | premium)
//    isActive:     Bool
//    sortOrder:    Int
//    params:       Map<String, Any>   (filter-specific config)
//    assetURLs:    Map<String, String> (textures, models, luts)
//    platforms:    [String]           (["ios", "android"] or specific)
//    createdAt:    Timestamp
//    updatedAt:    Timestamp
//  }
//

import Foundation
import FirebaseFirestore

// MARK: - Filter Category

enum FilterCategory: String, CaseIterable, Codable {
    case color       = "color"        // CIFilter color grades
    case face        = "face"         // ARKit face overlays
    case background  = "background"   // Segmentation / bg swap
    case world       = "world"        // World AR / environment
}

// MARK: - Filter Type (renderer)

enum FilterType: String, Codable {
    case ciFilter      = "cifilter"      // iOS CIFilter pipeline
    case arKit         = "arkit"         // ARKit face anchor
    case mlKit         = "mlkit"         // ML Kit (Android) or Vision (iOS)
    case segmentation  = "segmentation"  // Person segmentation
}

// MARK: - Filter Tier (access control)

enum FilterTier: String, Codable {
    case free       = "free"
    case subscriber = "subscriber"
    case premium    = "premium"
}

// MARK: - Filter Platform

enum FilterPlatform: String, Codable {
    case ios     = "ios"
    case android = "android"
}

// MARK: - FilterManifest

struct FilterManifest: Identifiable, Codable {
    let id:         String
    let name:       String
    let category:   FilterCategory
    let type:       FilterType
    let tier:       FilterTier
    var isActive:   Bool
    let sortOrder:  Int
    let params:     [String: Double]   // intensity ranges, param defaults
    let assetURLs:  [String: String]   // "lut" -> "https://...", "model" -> "https://..."
    let platforms:  [FilterPlatform]
    let createdAt:  Date
    let updatedAt:  Date

    // MARK: Firestore mapping

    static func from(_ doc: DocumentSnapshot) -> FilterManifest? {
        guard let data = doc.data() else { return nil }
        return FilterManifest(
            id:        doc.documentID,
            name:      data["name"]      as? String ?? "",
            category:  FilterCategory(rawValue: data["category"] as? String ?? "color") ?? .color,
            type:      FilterType(rawValue:     data["type"]     as? String ?? "cifilter") ?? .ciFilter,
            tier:      FilterTier(rawValue:     data["tier"]     as? String ?? "free") ?? .free,
            isActive:  data["isActive"]  as? Bool   ?? true,
            sortOrder: data["sortOrder"] as? Int    ?? 0,
            params:    data["params"]    as? [String: Double] ?? [:],
            assetURLs: data["assetURLs"] as? [String: String] ?? [:],
            platforms: (data["platforms"] as? [String] ?? ["ios", "android"])
                .compactMap { FilterPlatform(rawValue: $0) },
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    func toFirestore() -> [String: Any] {
        [
            "name":       name,
            "category":   category.rawValue,
            "type":       type.rawValue,
            "tier":       tier.rawValue,
            "isActive":   isActive,
            "sortOrder":  sortOrder,
            "params":     params,
            "assetURLs":  assetURLs,
            "platforms":  platforms.map(\.rawValue),
            "createdAt":  Timestamp(date: createdAt),
            "updatedAt":  Timestamp(date: updatedAt)
        ]
    }
}

// MARK: - Seed Data (run once to populate Firestore)

struct FilterSeed {
    static func seedFilters() async {
        let db = Firestore.firestore(database: "stitchfin")
        let filters = defaultFilters
        let batch = db.batch()
        for filter in filters {
            let ref = db.collection("filters").document(filter.id)
            batch.setData(filter.toFirestore(), forDocument: ref)
        }
        try? await batch.commit()
        print("🌱 FILTERS: Seeded \(filters.count) filters to Firestore")
    }

    static let defaultFilters: [FilterManifest] = [
        // Color grades
        .init(id: "color_vivid",      name: "Vivid",      category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 1,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_warm",       name: "Warm",       category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 2,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_cool",       name: "Cool",       category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 3,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_dramatic",   name: "Dramatic",   category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 4,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_cinematic",  name: "Cinematic",  category: .color, type: .ciFilter, tier: .subscriber, isActive: true, sortOrder: 5,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_vintage",    name: "Vintage",    category: .color, type: .ciFilter, tier: .subscriber, isActive: true, sortOrder: 6,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_monochrome", name: "Monochrome", category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 7,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        .init(id: "color_sunset",     name: "Sunset",     category: .color, type: .ciFilter, tier: .free,       isActive: true, sortOrder: 8,  params: ["intensity": 1.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
        // Face filters (ARKit — iOS only for now)
        .init(id: "face_beauty",      name: "Beauty",     category: .face, type: .arKit, tier: .free,       isActive: true, sortOrder: 10, params: ["smoothing": 0.5, "brightness": 0.2], assetURLs: [:], platforms: [.ios], createdAt: Date(), updatedAt: Date()),
        .init(id: "face_dog",         name: "Dog",        category: .face, type: .arKit, tier: .free,       isActive: false, sortOrder: 11, params: [:], assetURLs: ["model": ""], platforms: [.ios], createdAt: Date(), updatedAt: Date()),
        // Background
        .init(id: "bg_blur",          name: "Blur BG",    category: .background, type: .segmentation, tier: .subscriber, isActive: false, sortOrder: 20, params: ["blurRadius": 15.0], assetURLs: [:], platforms: [.ios, .android], createdAt: Date(), updatedAt: Date()),
    ]
}