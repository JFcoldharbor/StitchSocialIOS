//
//  CaptionOverlayView.swift
//  StitchSocial
//
//  Created by James Garmon on 12/14/25.
//


//
//  CaptionOverlayView.swift
//  StitchSocial
//
//  Layer 8: Views - Caption Overlay Renderer
//  Dependencies: VideoEditState
//  Features: Renders captions over video with positioning and styling
//

import SwiftUI

struct CaptionOverlayView: View {
    
    let captions: [VideoCaption]
    let currentTime: TimeInterval
    let videoSize: CGSize
    
    // Get active captions at current playback time
    private var activeCaptions: [VideoCaption] {
        captions.filter { caption in
            currentTime >= caption.startTime &&
            currentTime <= caption.endTime
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(activeCaptions) { caption in
                    StyledCaptionText(caption: caption)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * caption.position.offset
                        )
                }
            }
        }
    }
}

// MARK: - Styled Caption Text

struct StyledCaptionText: View {
    
    let caption: VideoCaption
    
    var body: some View {
        Text(caption.text)
            .font(.system(size: caption.style.fontSize, weight: fontWeight))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(captionBackground)
            .modifier(CaptionStyleModifier(style: caption.style))
    }
    
    private var fontWeight: Font.Weight {
        switch caption.style.fontWeight {
        case "bold": return .bold
        case "semibold": return .semibold
        default: return .semibold
        }
    }
    
    @ViewBuilder
    private var captionBackground: some View {
        switch caption.style {
        case .standard, .bold:
            Capsule()
                .fill(Color.black.opacity(0.7))
        case .outlined:
            EmptyView()
        case .shadow:
            Capsule()
                .fill(Color.black.opacity(0.5))
        }
    }
}

// MARK: - Caption Style Modifier

struct CaptionStyleModifier: ViewModifier {
    
    let style: CaptionStyle
    
    func body(content: Content) -> some View {
        switch style {
        case .standard, .bold:
            content
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            
        case .outlined:
            content
                .overlay(
                    // Text outline using stroke
                    content
                        .foregroundColor(.black)
                        .offset(x: -1, y: -1)
                )
                .overlay(
                    content
                        .foregroundColor(.black)
                        .offset(x: 1, y: -1)
                )
                .overlay(
                    content
                        .foregroundColor(.black)
                        .offset(x: -1, y: 1)
                )
                .overlay(
                    content
                        .foregroundColor(.black)
                        .offset(x: 1, y: 1)
                )
            
        case .shadow:
            content
                .shadow(color: .black.opacity(0.8), radius: 8, x: 0, y: 4)
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        }
    }
}

// MARK: - Draggable Caption (for positioning UI)

struct DraggableCaptionView: View {
    
    @Binding var caption: VideoCaption
    let videoSize: CGSize
    let onPositionChanged: (CaptionPosition) -> Void
    
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            StyledCaptionText(caption: caption)
                .position(
                    x: geometry.size.width / 2 + dragOffset.width,
                    y: (geometry.size.height * caption.position.offset) + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            updatePosition(
                                offset: value.translation,
                                in: geometry.size
                            )
                            dragOffset = .zero
                        }
                )
        }
    }
    
    private func updatePosition(offset: CGSize, in size: CGSize) {
        let finalY = (size.height * caption.position.offset) + offset.height
        let normalizedY = finalY / size.height
        
        // Determine new position based on normalized Y
        let newPosition: CaptionPosition
        if normalizedY < 0.33 {
            newPosition = .top
        } else if normalizedY > 0.66 {
            newPosition = .bottom
        } else {
            newPosition = .center
        }
        
        if newPosition != caption.position {
            onPositionChanged(newPosition)
        }
    }
}