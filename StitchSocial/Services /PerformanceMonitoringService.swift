import Foundation
import FirebasePerformance

/// Service for monitoring app performance using Firebase Performance
class PerformanceMonitoringService {
    static let shared = PerformanceMonitoringService()
    
    private var activeTraces: [String: Trace] = [:]
    
    private init() {}
    
    // MARK: - Video Performance Tracking
    
    /// Start tracking video load performance
    @discardableResult
    func startVideoLoadTrace(videoId: String) -> Trace? {
        guard let trace = Performance.startTrace(name: "video_load_\(videoId)") else {
            return nil
        }
        trace.setValue("video", forAttribute: "content_type")
        trace.setValue(videoId, forAttribute: "video_id")
        activeTraces["video_load_\(videoId)"] = trace
        return trace
    }
    
    /// Complete video load tracking
    func stopVideoLoadTrace(videoId: String, success: Bool) {
        let key = "video_load_\(videoId)"
        guard let trace = activeTraces[key] else { return }
        trace.setValue(success ? "success" : "failure", forAttribute: "status")
        trace.stop()
        activeTraces.removeValue(forKey: key)
    }
    
    /// Track video playback start time
    func trackVideoPlaybackStart(videoId: String) {
        guard let trace = Performance.startTrace(name: "video_playback_start") else {
            return
        }
        trace.setValue(videoId, forAttribute: "video_id")
        trace.stop()
    }
    
    // MARK: - Feed Performance Tracking
    
    /// Start tracking feed load performance
    @discardableResult
    func startFeedLoadTrace() -> Trace? {
        guard let trace = Performance.startTrace(name: "home_feed_load") else {
            return nil
        }
        trace.setValue("feed", forAttribute: "screen")
        activeTraces["home_feed_load"] = trace
        return trace
    }
    
    /// Complete feed load tracking
    func stopFeedLoadTrace(videoCount: Int) {
        guard let trace = activeTraces["home_feed_load"] else { return }
        trace.incrementMetric("video_count", by: Int64(videoCount))
        trace.stop()
        activeTraces.removeValue(forKey: "home_feed_load")
    }
    
    // MARK: - Search Performance Tracking
    
    /// Track search query performance
    func trackSearchQuery(query: String, resultCount: Int, duration: TimeInterval) {
        guard let trace = Performance.startTrace(name: "search_query") else {
            return
        }
        trace.setValue(query.isEmpty ? "empty" : "with_text", forAttribute: "query_type")
        trace.incrementMetric("result_count", by: Int64(resultCount))
        trace.incrementMetric("duration_ms", by: Int64(duration * 1000))
        trace.stop()
    }
    
    // MARK: - Upload Performance Tracking
    
    /// Start tracking video upload performance
    @discardableResult
    func startVideoUploadTrace(fileSize: Int64) -> Trace? {
        guard let trace = Performance.startTrace(name: "video_upload") else {
            return nil
        }
        trace.setValue("upload", forAttribute: "operation_type")
        trace.incrementMetric("file_size_bytes", by: fileSize)
        activeTraces["video_upload"] = trace
        return trace
    }
    
    /// Complete video upload tracking
    func stopVideoUploadTrace(success: Bool, error: String? = nil) {
        guard let trace = activeTraces["video_upload"] else { return }
        trace.setValue(success ? "success" : "failure", forAttribute: "status")
        if let error = error {
            trace.setValue(error, forAttribute: "error")
        }
        trace.stop()
        activeTraces.removeValue(forKey: "video_upload")
    }
    
    // MARK: - AI Processing Performance
    
    /// Track AI content generation performance
    func trackAIProcessing(operation: String, duration: TimeInterval, success: Bool) {
        guard let trace = Performance.startTrace(name: "ai_processing") else {
            return
        }
        trace.setValue(operation, forAttribute: "ai_operation")
        trace.setValue(success ? "success" : "failure", forAttribute: "status")
        trace.incrementMetric("duration_ms", by: Int64(duration * 1000))
        trace.stop()
    }
    
    // MARK: - Network Performance Tracking
    
    /// Track custom network request performance
    func trackNetworkRequest(url: String, method: String, statusCode: Int, duration: TimeInterval) {
        guard let trace = Performance.startTrace(name: "network_request") else {
            return
        }
        trace.setValue(method, forAttribute: "http_method")
        trace.setValue("\(statusCode)", forAttribute: "status_code")
        trace.incrementMetric("duration_ms", by: Int64(duration * 1000))
        trace.stop()
    }
    
    // MARK: - Screen Performance Tracking
    
    /// Track screen load time
    func trackScreenLoad(screenName: String, duration: TimeInterval) {
        guard let trace = Performance.startTrace(name: "screen_load") else {
            return
        }
        trace.setValue(screenName, forAttribute: "screen_name")
        trace.incrementMetric("load_time_ms", by: Int64(duration * 1000))
        trace.stop()
    }
    
    // MARK: - Memory Performance
    
    /// Track memory-intensive operations
    func trackMemoryOperation(operation: String, memoryUsed: Int64) {
        guard let trace = Performance.startTrace(name: "memory_operation") else {
            return
        }
        trace.setValue(operation, forAttribute: "operation")
        trace.incrementMetric("memory_bytes", by: memoryUsed)
        trace.stop()
    }
    
    // MARK: - Generic Trace Management
    
    /// Start a custom trace
    @discardableResult
    func startTrace(name: String, attributes: [String: String] = [:]) -> Trace? {
        guard let trace = Performance.startTrace(name: name) else {
            return nil
        }
        for (key, value) in attributes {
            trace.setValue(value, forAttribute: key)
        }
        activeTraces[name] = trace
        return trace
    }
    
    /// Stop a custom trace
    func stopTrace(name: String, metrics: [String: Int64] = [:]) {
        guard let trace = activeTraces[name] else { return }
        for (key, value) in metrics {
            trace.incrementMetric(key, by: value)
        }
        trace.stop()
        activeTraces.removeValue(forKey: name)
    }
    
    // MARK: - HTTP Metric (Automatic Network Monitoring)
    
    /// Track HTTP request performance
    func trackHTTPRequest(url: URL, method: String, statusCode: Int, startTime: Date) {
        let duration = Date().timeIntervalSince(startTime)
        trackNetworkRequest(
            url: url.absoluteString,
            method: method,
            statusCode: statusCode,
            duration: duration
        )
    }
}

// MARK: - Performance Extensions

extension PerformanceMonitoringService {
    /// Track video preloading performance
    func trackVideoPreload(videoId: String, success: Bool, duration: TimeInterval) {
        guard let trace = Performance.startTrace(name: "video_preload") else {
            return
        }
        trace.setValue(videoId, forAttribute: "video_id")
        trace.setValue(success ? "success" : "failure", forAttribute: "status")
        trace.incrementMetric("duration_ms", by: Int64(duration * 1000))
        trace.stop()
    }
    
    /// Track collection load performance
    func trackCollectionLoad(collectionId: String, segmentCount: Int, duration: TimeInterval) {
        guard let trace = Performance.startTrace(name: "collection_load") else {
            return
        }
        trace.setValue(collectionId, forAttribute: "collection_id")
        trace.incrementMetric("segment_count", by: Int64(segmentCount))
        trace.incrementMetric("duration_ms", by: Int64(duration * 1000))
        trace.stop()
    }
}
