//
//  FeedCache.swift
//  StitchSocial
//
//  Layer 4: Services - Offline Feed Cache
//  Features: Cache videos for offline scrolling like TikTok
//

import Foundation

/// Lightweight cache for offline feed viewing
class FeedCache {
    
    static let shared = FeedCache()
    
    private let cacheKey = "cached_home_feed"
    private let cacheTimestampKey = "cached_home_feed_timestamp"
    private let maxCachedThreads = 10 // Cache first 10 threads for offline
    private let cacheExpirationHours: Double = 24 // Cache valid for 24 hours
    
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
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
            print("💾 FEED CACHE: Saved \(threadsToCache.count) threads for offline viewing")
        } catch {
            print("❌ FEED CACHE: Failed to save - \(error)")
        }
    }
    
    // MARK: - Load Cached Feed
    
    func loadCachedFeed() -> [ThreadData]? {
        // Check if cache exists and is not expired
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? TimeInterval else {
            print("📭 FEED CACHE: No cached feed found")
            return nil
        }
        
        let cacheAge = Date().timeIntervalSince1970 - timestamp
        let maxAge = cacheExpirationHours * 3600
        
        if cacheAge > maxAge {
            print("⏰ FEED CACHE: Cache expired (\(Int(cacheAge/3600))h old)")
            clearCache()
            return nil
        }
        
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let threads = try decoder.decode([ThreadData].self, from: data)
            print("✅ FEED CACHE: Loaded \(threads.count) cached threads (age: \(Int(cacheAge/60))min)")
            return threads
        } catch {
            print("❌ FEED CACHE: Failed to decode - \(error)")
            clearCache()
            return nil
        }
    }
    
    // MARK: - Check Cache Status
    
    func hasCachedFeed() -> Bool {
        return loadCachedFeed() != nil
    }
    
    func cacheAge() -> TimeInterval? {
        guard let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? TimeInterval else {
            return nil
        }
        return Date().timeIntervalSince1970 - timestamp
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        print("🗑️ FEED CACHE: Cleared")
    }
}

// MARK: - Network Reachability Helper

import Network

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
                    print("📵 NETWORK: Offline - using cached content")
                } else {
                    print("📶 NETWORK: Online via \(self?.connectionType ?? .unknown)")
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
