//
//  LocationChip.swift
//  StitchSocial
//
//  Compact, tappable place pill rendered on top of a video. Drop into any
//  overlay layer like:
//      if let place = video.place {
//          LocationChip(location: place) { /* tap → place feed */ }
//      }
//
//  Visual: ultra-thin material background, SF Symbol category icon, single
//  line truncated name. Sized to read cleanly at the bottom-left of a 9:16
//  video without obscuring content.
//

import SwiftUI

struct LocationChip: View {

    let location: VideoLocation
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 6) {
                Image(systemName: location.placeType.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(location.displayLine)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Location: \(location.displayLine)")
    }
}

// MARK: - Decoder Helper

extension VideoLocation {
    /// Decode a `VideoLocation` out of the nested `place` map written by
    /// `VideoUploadService`. Returns nil if any required field is missing
    /// so the chip is simply omitted on legacy/no-location videos.
    static func decode(from placeData: [String: Any]?) -> VideoLocation? {
        guard let data = placeData,
              let id = data["id"] as? String,
              let name = data["name"] as? String,
              let lat = data["latitude"] as? Double,
              let lng = data["longitude"] as? Double else {
            return nil
        }
        let typeRaw = data["placeType"] as? String ?? VideoPlaceType.other.rawValue
        let type = VideoPlaceType(rawValue: typeRaw) ?? .other
        return VideoLocation(
            id: id,
            name: name,
            address: data["address"] as? String ?? "",
            latitude: lat,
            longitude: lng,
            placeType: type
        )
    }

    /// Memberwise init exposed so decoders / tests can construct directly.
    init(
        id: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        placeType: VideoPlaceType
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.placeType = placeType
    }
}
