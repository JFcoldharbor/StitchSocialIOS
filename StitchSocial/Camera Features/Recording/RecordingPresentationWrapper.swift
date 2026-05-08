//
//  RecordingPresentationWrappers.swift
//  StitchSocial
//
//  Layer 8: Stable wrappers for RecordingView presentation
//
//  PROBLEM: fullScreenCover recreates its content when the parent body
//  re-evaluates (Firebase listeners, state changes, etc.). This destroys
//  @StateObject RecordingController inside RecordingView.
//
//  SOLUTION: These wrappers own the controller as @StateObject.
//  The wrapper struct is stable — its init params (bindings + closures)
//  don't change identity, so SwiftUI preserves the @StateObject.
//
//  StableRecordingCover — for ContentView / MainTabContainer (new thread)
//  StitchRecordingCover — for ContextualVideoOverlay (stitch/reply, dynamic context)
//

import SwiftUI

// MARK: - Stable Recording Cover (New Thread)

struct StableRecordingCover: View {
    @Binding var showingRecording: Bool
    let onVideoCreated: (CoreVideoMetadata) -> Void

    @StateObject private var controller = RecordingController(recordingContext: .newThread)

    var body: some View {
        RecordingView(
            controller: controller,
            onVideoCreated: { metadata in
                onVideoCreated(metadata)
            },
            onCancel: {
                showingRecording = false
            }
        )
    }
}

// MARK: - Stitch Recording Cover (Dynamic Context)

struct StitchRecordingCover: View {
    @Binding var isPresented: Bool
    let getContext: () -> RecordingContext
    let onVideoCreated: ((CoreVideoMetadata) -> Void)?

    @StateObject private var controller = RecordingController(recordingContext: .newThread)

    var body: some View {
        RecordingView(
            controller: controller,
            onVideoCreated: { metadata in
                isPresented = false
                onVideoCreated?(metadata)
            },
            onCancel: {
                isPresented = false
            }
        )
        .onAppear {
            // Update context each time cover appears —
            // supports stitch vs reply based on video depth
            controller.recordingContext = getContext()
        }
    }
}
