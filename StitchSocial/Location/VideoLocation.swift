//
//  VideoLocation.swift
//  StitchSocial
//
//  Place metadata attached to a video — restaurant, monument, park, address.
//  Source: Apple MKLocalSearch (free, built into iOS, MapKit).
//
//  Stored as a nested map on the video doc so a single read returns everything
//  needed to render the location chip; no extra Firestore round trip.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Place Type

/// Broad category used for filtering and iconography. Not exhaustive —
/// MKLocalSearch returns Apple's point-of-interest categories which are
/// granular (bakery, sushi, park, museum, etc.); we collapse them into
/// the buckets that actually matter for our content.
enum VideoPlaceType: String, Codable, CaseIterable {
    case restaurant   // food / drink (incl. cafes, bars, bakeries)
    case attraction   // monument, museum, landmark, tourist site
    case outdoor      // park, beach, trail, viewpoint
    case venue        // concert hall, stadium, theater
    case retail       // store, mall
    case address      // generic address with no specific business
    case other

    /// Apple SF Symbol used in the LocationChip + picker rows.
    var iconName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .attraction: return "building.columns"
        case .outdoor:    return "leaf"
        case .venue:      return "music.mic"
        case .retail:     return "bag"
        case .address:    return "mappin"
        case .other:      return "mappin.and.ellipse"
        }
    }

    /// Map an MKMapItem's point-of-interest category into our buckets.
    /// Falls back to .other when Apple returns no category (e.g. raw geocode).
    static func from(_ category: MKPointOfInterestCategory?) -> VideoPlaceType {
        guard let category = category else { return .address }
        switch category {
        case .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife, .foodMarket:
            return .restaurant
        case .museum, .landmark, .nationalMonument, .castle, .planetarium, .library:
            return .attraction
        case .park, .beach, .nationalPark, .campground, .hiking, .fishing, .surfing:
            return .outdoor
        case .stadium, .musicVenue, .theater, .movieTheater, .conventionCenter:
            return .venue
        case .store, .marina, .pharmacy:
            return .retail
        default:
            return .other
        }
    }
}

// MARK: - VideoLocation

/// Place attached to a video post. Codable for Firestore storage and decoding
/// directly off a snapshot. All fields are required except `placeType` and
/// `address`, both of which can be empty for raw geocoded pins.
struct VideoLocation: Codable, Equatable, Hashable, Identifiable {
    /// Apple's persistent identifier for the place, or a synthesized hash for
    /// raw coordinates. Used to dedupe + key the future Place feed page.
    let id: String

    /// User-facing name. "Joe's Pizza", "Eiffel Tower", "21st & Mission".
    let name: String

    /// Full street address. May be empty for natural landmarks.
    let address: String

    let latitude: Double
    let longitude: Double

    /// Broad category for iconography + filters.
    let placeType: VideoPlaceType

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: Convenience builders

    /// Build from an MKMapItem returned by MKLocalSearch.
    init(mapItem: MKMapItem) {
        let coord = mapItem.placemark.coordinate
        self.latitude = coord.latitude
        self.longitude = coord.longitude
        self.name = mapItem.name ?? "Unnamed Place"
        self.address = Self.formatAddress(from: mapItem.placemark)
        self.placeType = VideoPlaceType.from(mapItem.pointOfInterestCategory)
        // MKMapItem.identifier is iOS 18+. For older systems fall back to a
        // coordinate-derived hash so two videos at the same pin still dedupe.
        if #available(iOS 18.0, *), let mkID = mapItem.identifier?.rawValue {
            self.id = mkID
        } else {
            self.id = "coord_\(Self.hashCoord(coord))"
        }
    }

    /// Compact one-line representation used by the location chip overlay.
    /// Falls back to coordinate if both name and address are missing.
    var displayLine: String {
        if !name.isEmpty { return name }
        if !address.isEmpty { return address }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    // MARK: - Helpers

    private static func formatAddress(from placemark: MKPlacemark) -> String {
        // Prefer the structured address fields over `title` since `title`
        // sometimes duplicates the place name.
        let parts: [String?] = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
        ]
        let line = parts.compactMap { $0 }.joined(separator: " ")
        return line.isEmpty ? (placemark.title ?? "") : line
    }

    private static func hashCoord(_ c: CLLocationCoordinate2D) -> String {
        // Round to ~11m so two videos taken near the same spot share an id.
        let lat = (c.latitude * 10_000).rounded() / 10_000
        let lng = (c.longitude * 10_000).rounded() / 10_000
        return "\(lat)_\(lng)"
    }
}
