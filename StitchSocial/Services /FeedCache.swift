//
//  FeedCache.swift
//  StitchSocial
//
//  Layer 4: Services - Offline Feed Cache
//  Features: Cache videos for offline scrolling like TikTok
//

import Foundation
import Network

/// Lightweight cache for offline feed viewing
class FeedCache {
    
    static let shared = FeedCache()
    
    private let cacheKey = "cached_home_feed"
    private let cacheTimestampKey = "cached_home_feed_timestamp"
    private let maxCachedThreads = 10 // Cache first 10 threads for offline
    private let cacheExpirationHours: Double = 24 // Cache valid for 24 hours
    
    // MARK: - In-Memory Cache (avoid repeated UserDefaults reads)
    
    private var memoryCache: [ThreadData]?
    private var memoryCacheTimestamp: TimeInterval?
    
    private init() {}
    
    // MARK: - Cache Feed
    
    func cacheFeed(_ threads: [ThreadData]) {
        guard !threads.isEmpty else { return }
        
        // Only cache first N threads
        let threadsToCache = Array(threads.prefix(maxCachedThreads))
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(threadsToCache)
            UserDefaults.standard.set(data, forKey: cacheKey)
            
            let now = Date().timeIntervalSince1970
            UserDefaults.standard.set(now, forKey: cacheTimestampKey)
            
            // Update memory cache
            memoryCache = threadsToCache
            memoryCacheTimestamp = now
            
            #if DEBUG
            print("💾 FEED CACHE: Saved \(threadsToCache.count) threads for offline viewing")
            #endif
        } catch {
            #if DEBUG
            print("❌ FEED CACHE: Failed to save - \(error)")
            #endif
        }
    }
    
    // MARK: - Load Cached Feed
    
    func loadCachedFeed() -> [ThreadData]? {
        // Return from memory if valid
        if let cached = memoryCache, let timestamp = memoryCacheTimestamp {
            if !isCacheExpired(timestamp) {
                return cached
            }
        }
        
        // Check timestamp first (cheap)
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? TimeInterval else {
            #if DEBUG
            print("📭 FEED CACHE: No cached feed found")
            #endif
            return nil
        }
        
        // Check expiration
        if isCacheExpired(timestamp) {
            let cacheAge = Date().timeIntervalSince1970 - timestamp
            #if DEBUG
            print("⏰ FEED CACHE: Cache expired (\(Int(cacheAge/3600))h old)")
            #endif
            clearCache()
            return nil
        }
        
        // Only decode if cache is valid
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let threads = try decoder.decode([ThreadData].self, from: data)
            
            // Update memory cache
            memoryCache = threads
            memoryCacheTimestamp = timestamp
            
            let cacheAge = Date().timeIntervalSince1970 - timestamp
            #if DEBUG
            print("✅ FEED CACHE: Loaded \(threads.count) cached threads (age: \(Int(cacheAge/60))min)")
            #endif
            return threads
        } catch {
            #if DEBUG
            print("❌ FEED CACHE: Failed to decode - \(error)")
            #endif
            clearCache()
            return nil
        }
    }
    
    // MARK: - Check Cache Status (OPTIMIZED)
    
    func hasCachedFeed() -> Bool {
        // Check memory cache first
        if let timestamp = memoryCacheTimestamp {
            return !isCacheExpired(timestamp)
        }
        
        // Check UserDefaults timestamp only (no decode)
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? TimeInterval else {
            return false
        }
        
        return !isCacheExpired(timestamp)
    }
    
    func cacheAge() -> TimeInterval? {
        // Check memory cache first
        if let timestamp = memoryCacheTimestamp {
            return Date().timeIntervalSince1970 - timestamp
        }
        
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? TimeInterval else {
            return nil
        }
        return Date().timeIntervalSince1970 - timestamp
    }
    
    // MARK: - Helper
    
    private func isCacheExpired(_ timestamp: TimeInterval) -> Bool {
        let cacheAge = Date().timeIntervalSince1970 - timestamp
        return cacheAge > (cacheExpirationHours * 3600)
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        memoryCache = nil
        memoryCacheTimestamp = nil
        #if DEBUG
        print("🗑️ FEED CACHE: Cleared")
        #endif
    }
}

// MARK: - Network Reachability Helper

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi
        case cellular
        case unknown
    }
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
                
                if path.status != .satisfied {
                    #if DEBUG
                    print("📵 NETWORK: Offline - using cached content")
                    #endif
                } else {
                    #if DEBUG
                    print("📶 NETWORK: Online via \(self?.connectionType ?? .unknown)")
                    #endif
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .unknown
    }
}
