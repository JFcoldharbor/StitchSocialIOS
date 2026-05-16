//
//  LocationPickerView.swift
//  StitchSocial
//
//  SwiftUI sheet for attaching a place to a video. Present from the post-record
//  metadata screen via `.sheet`. Returns a `VideoLocation` via the callback.
//
//  Usage:
//      .sheet(isPresented: $showPicker) {
//          LocationPickerView { selected in
//              self.selectedLocation = selected
//          }
//      }
//

import SwiftUI
import CoreLocation
import MapKit

struct LocationPickerView: View {

    // MARK: - Inputs

    /// Called when the user taps a result. Caller is responsible for dismissing.
    let onSelect: (VideoLocation) -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = LocationService()

    @State private var query: String = ""
    @State private var results: [VideoLocation] = []
    @State private var nearbyResults: [VideoLocation] = []
    @State private var searchTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField
                    Divider().background(Color.gray.opacity(0.3))

                    if !query.isEmpty {
                        searchResultsList
                    } else {
                        nearbyList
                    }
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.cyan)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if service.isSearching {
                        ProgressView().tint(.cyan)
                    }
                }
            }
            .task {
                await primeNearby()
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search places, restaurants, addresses…", text: $query)
                .foregroundColor(.white)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .onChange(of: query) { _ in
                    debounceSearch()
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Nearby List

    @ViewBuilder
    private var nearbyList: some View {
        if !service.canUseDeviceLocation {
            grantPrompt
        } else if nearbyResults.isEmpty && !service.isSearching {
            emptyNearby
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    sectionHeader("Nearby")
                    ForEach(nearbyResults) { place in
                        row(for: place)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var grantPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            Text("Turn on location to see places near you.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            Button("Allow Location") {
                service.requestAuthorization()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.cyan)
            .foregroundColor(.black)
            .cornerRadius(12)
            Text("You can also search by name above.")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyNearby: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.gray)
            Text("Looking for nearby places…")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search Results List

    @ViewBuilder
    private var searchResultsList: some View {
        if results.isEmpty && !service.isSearching {
            VStack(spacing: 8) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 36))
                    .foregroundColor(.gray)
                Text("No places matching \"\(query)\"")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { place in
                        row(for: place)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Row

    private func row(for place: VideoLocation) -> some View {
        Button {
            onSelect(place)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: place.placeType.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cyan)
                    .frame(width: 36, height: 36)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundColor(.gray)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Search debounce

    private func debounceSearch() {
        searchTask?.cancel()
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms debounce
            guard !Task.isCancelled else { return }
            let region = service.currentLocation.map {
                MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 5_000, longitudinalMeters: 5_000)
            }
            let res = (try? await service.search(query: q, near: region)) ?? []
            guard !Task.isCancelled else { return }
            self.results = res
        }
    }

    // MARK: - Nearby priming

    private func primeNearby() async {
        if service.authorizationStatus == .notDetermined {
            service.requestAuthorization()
        }
        guard service.canUseDeviceLocation else { return }
        do {
            let loc = try await service.fetchCurrentLocation()
            let places = try await service.nearby(loc)
            self.nearbyResults = places
        } catch {
            #if DEBUG
            print("⚠️ LOCATION: Nearby fetch failed — \(error)")
            #endif
        }
    }
}
