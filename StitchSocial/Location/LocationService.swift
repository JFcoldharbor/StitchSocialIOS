//
//  LocationService.swift
//  StitchSocial
//
//  Thin wrapper around CoreLocation + MKLocalSearch that powers the location
//  picker. Two responsibilities:
//    1. Request "When In Use" authorization and surface the result reactively.
//    2. Run nearby + keyword searches that return `[VideoLocation]`.
//
//  Note on auth: `NSLocationWhenInUseUsageDescription` is already declared in
//  Info.plist. If you change the user-facing description, edit Info.plist.
//

import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isSearching = false
    @Published private(set) var lastError: String?

    // MARK: - Private

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    // MARK: - Init

    override init() {
        self.authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Authorization

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Convenience — returns true if we can read the device location right now.
    var canUseDeviceLocation: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    // MARK: - One-shot location fetch

    /// Resolve the current device location. Throws if denied or times out.
    /// Used by the picker when the user taps "Use Current Location".
    func fetchCurrentLocation() async throws -> CLLocation {
        if let recent = currentLocation,
           recent.timestamp.timeIntervalSinceNow > -30 {
            return recent
        }
        return try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            manager.requestLocation()
        }
    }

    // MARK: - Place Search

    /// Search by user-typed text. Optionally anchored to a region for ranking.
    /// `MKLocalSearch` charges no quota for app developers — Apple covers it.
    func search(query: String, near region: MKCoordinateRegion? = nil) async throws -> [VideoLocation] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let region = region {
            request.region = region
        }
        return try await runSearch(request)
    }

    /// "Nearby" search anchored to the user's location. We use a small search
    /// region (~1km) and a wildcard query so the response is sorted by distance.
    func nearby(_ location: CLLocation, radiusMeters: CLLocationDistance = 1_000) async throws -> [VideoLocation] {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
        let request = MKLocalSearch.Request()
        request.region = region
        // MKLocalSearch requires a query string. " " (a space) is the trick
        // Apple's own apps use to mean "anything in this region."
        request.naturalLanguageQuery = " "
        request.resultTypes = [.pointOfInterest]
        return try await runSearch(request)
    }

    // MARK: - Private

    private func runSearch(_ request: MKLocalSearch.Request) async throws -> [VideoLocation] {
        isSearching = true
        defer { isSearching = false }

        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            #if DEBUG
            print("❌ LOCATION: MKLocalSearch failed — \(error)")
            #endif
            lastError = error.localizedDescription
            throw error
        }

        return response.mapItems.map { VideoLocation(mapItem: $0) }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = loc
            self.locationContinuation?.resume(returning: loc)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }
}
