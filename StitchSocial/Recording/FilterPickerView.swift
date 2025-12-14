//
//  FilterPickerView.swift
//  StitchSocial
//
//  Created by James Garmon on 12/14/25.
//


//
//  FilterPickerView.swift
//  StitchSocial
//
//  Layer 8: Views - Filter Selection Grid
//  Dependencies: VideoEditState, FilterLibrary
//  Features: Grid of filter previews with live preview
//

import SwiftUI

struct FilterPickerView: View {
    
    @ObservedObject var editState: VideoEditStateManager
    
    @State private var selectedFilter: VideoFilter?
    @State private var filterIntensity: Double = 1.0
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Instructions
            Text("Choose a filter to enhance your video")
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .padding(.top, 20)
                .padding(.bottom, 16)
            
            // Filter grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(VideoFilter.allCases, id: \.self) { filter in
                        FilterThumbnail(
                            filter: filter,
                            isSelected: selectedFilter == filter,
                            onTap: {
                                selectFilter(filter)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Intensity slider (if filter selected)
            if let filter = selectedFilter, filter != .none {
                VStack(spacing: 12) {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 20)
                    
                    HStack(spacing: 16) {
                        Image(systemName: "circle")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Slider(value: $filterIntensity, in: 0...1)
                            .accentColor(.cyan)
                            .onChange(of: filterIntensity) { _, newValue in
                                updateIntensity(newValue)
                            }
                        
                        Image(systemName: "circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.cyan)
                        
                        Text("\(Int(filterIntensity * 100))%")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 45)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            selectedFilter = editState.state.selectedFilter
            filterIntensity = editState.state.filterIntensity
        }
    }
    
    // MARK: - Actions
    
    private func selectFilter(_ filter: VideoFilter) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if filter == .none {
                selectedFilter = nil
                editState.state.setFilter(nil)
            } else {
                selectedFilter = filter
                editState.state.setFilter(filter, intensity: filterIntensity)
            }
        }
    }
    
    private func updateIntensity(_ intensity: Double) {
        if let filter = selectedFilter {
            editState.state.setFilter(filter, intensity: intensity)
        }
    }
}

// MARK: - Filter Thumbnail

struct FilterThumbnail: View {
    
    let filter: VideoFilter
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Filter preview circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: filterGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(
                                    isSelected ?
                                    Color.cyan : Color.white.opacity(0.2),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                        .shadow(
                            color: isSelected ? Color.cyan.opacity(0.5) : Color.clear,
                            radius: 8,
                            x: 0,
                            y: 0
                        )
                    
                    Image(systemName: filter.thumbnailIcon)
                        .font(.system(size: 28, weight: isSelected ? .bold : .regular))
                        .foregroundColor(.white)
                }
                
                // Filter name
                Text(filter.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .cyan : .white)
                    .lineLimit(1)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0) {} onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }
    
    private var filterGradientColors: [Color] {
        switch filter {
        case .none:
            return [Color(white: 0.3), Color(white: 0.2)]
        case .vivid:
            return [.pink, .orange, .yellow]
        case .warm:
            return [.orange, .red, .pink]
        case .cool:
            return [.cyan, .blue, .purple]
        case .dramatic:
            return [.black, .gray, .white]
        case .vintage:
            return [.brown, .orange, .yellow.opacity(0.5)]
        case .monochrome:
            return [.white, .gray, .black]
        case .cinematic:
            return [.black.opacity(0.8), .gray.opacity(0.5)]
        case .sunset:
            return [.orange, .pink, .purple]
        }
    }
}

// MARK: - Filter Library (Helper)

/// Provides filter application utilities
struct FilterLibrary {
    
    /// Get CIFilter instance for video filter
    static func createFilter(_ filter: VideoFilter, intensity: Double) -> CIFilter? {
        guard let filterName = filter.ciFilterName else { return nil }
        
        let ciFilter = CIFilter(name: filterName)
        
        // Configure filter parameters based on type
        switch filter {
        case .vivid:
            ciFilter?.setValue(1.0 + intensity * 0.5, forKey: kCIInputSaturationKey)
            ciFilter?.setValue(intensity * 0.2, forKey: kCIInputContrastKey)
            
        case .warm:
            ciFilter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            ciFilter?.setValue(CIVector(x: 4000, y: 0), forKey: "inputTargetNeutral")
            
        case .cool:
            ciFilter?.setValue(CIVector(x: 4000, y: 0), forKey: "inputNeutral")
            ciFilter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
            
        case .dramatic:
            ciFilter?.setValue(1.0 + intensity * 0.8, forKey: kCIInputContrastKey)
            ciFilter?.setValue(intensity * 0.1, forKey: kCIInputBrightnessKey)
            
        case .cinematic:
            ciFilter?.setValue(intensity * 30, forKey: kCIInputRadiusKey)
            ciFilter?.setValue(intensity * 0.7, forKey: kCIInputIntensityKey)
            
        default:
            break
        }
        
        return ciFilter
    }
}