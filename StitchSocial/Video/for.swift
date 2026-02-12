//
//  VideoPlayerContext.swift
//  StitchSocial
//
//  Shared enum for video player context awareness.
//  Extracted from VideoPlayerView.swift so it can be used by
//  BoundedVideoContainer, ThreadNavigationView, and any future player.
//

import Foundation

enum VideoPlayerContext {
    case homeFeed
    case discovery
    case profileGrid
    case threadView
    case fullscreen
    case standalone
}

enum VideoNavigationDirection {
    case none
    case horizontal
    case vertical
    case previous
    case next
}
