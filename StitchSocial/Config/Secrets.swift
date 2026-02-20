//
//  Secrets.swift
//  StitchSocial
//
//  Created by James Garmon on 2/15/26.
//


// Secrets.swift
// StitchSocial
//
// Loads API keys from Secrets.plist (gitignored)
// Caching: static let reads plist ONCE from disk, cached in memory for app lifetime

import Foundation

enum Secrets {
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            print("⚠️ Secrets.plist not found - API keys will be empty")
            return [:]
        }
        return dict
    }()
    
    static var openAIKey: String {
        secrets["OpenAIAPIKey"] as? String ?? ""
    }
}