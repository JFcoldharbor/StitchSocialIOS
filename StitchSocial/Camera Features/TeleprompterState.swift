//
//  TeleprompterView.swift
//  StitchSocial
//
//  Text near top (close to lens), PiP preview bottom-right.
//  Inline size + speed controls on the recording screen.
//  CACHING: script + speed + fontSize in @AppStorage — persists sessions.

import SwiftUI
import AVFoundation

// MARK: - TeleprompterState

@MainActor
class TeleprompterState: ObservableObject {
    @AppStorage("tp_script")    var script: String    = ""
    @AppStorage("tp_speed")     var scrollSpeed: Double = 35.0
    @AppStorage("tp_fontSize")  var fontSize: Double   = 24.0

    @Published var isScrolling   = false
    @Published var scrollOffset: CGFloat = 0
    @Published var showEditor    = false

    private var scrollTimer: Timer?

    func startScrolling() {
        guard !script.isEmpty else { return }
        isScrolling = true
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.scrollOffset += CGFloat(self.scrollSpeed / 60.0) }
        }
    }

    func stopScrolling() {
        isScrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    func resetScroll() {
        stopScrolling()
        scrollOffset = 0
    }

    var hasScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - TeleprompterView

struct TeleprompterView: View {
    @ObservedObject var state: TeleprompterState
    @ObservedObject var cameraManager: CinematicCameraManager

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                scriptZone
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.55)
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    PiPPreviewView(cameraManager: cameraManager)
                        .frame(width: 85, height: 115)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .padding(.trailing, 14)
                        .padding(.bottom, 150)
                }
            }
        }
        .sheet(isPresented: $state.showEditor) {
            TeleprompterEditorSheet(state: state)
        }
    }

    private var scriptZone: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                if state.hasScript {
                    // Clip to zone so text doesn't bleed outside
                    VStack(spacing: 0) {
                        Spacer().frame(height: geo.size.height * 0.55) // start text in lower portion
                        Text(state.script)
                            .font(.system(size: state.fontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(8)
                            .padding(.horizontal, 20)
                            .offset(y: -state.scrollOffset)
                            .animation(.linear(duration: 0), value: state.scrollOffset)
                        Spacer()
                    }
                    .clipped()
                } else {
                    emptyPrompt
                }
            }
            .clipped()
        }
    }

    private var emptyPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.35))
            Text("Tap Edit Script to add your script")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inline Controls (used in RecordingView above record button)

struct TeleprompterControlBar: View {
    @ObservedObject var state: TeleprompterState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: $state.fontSize, in: 16...40, step: 2)
                        .tint(.white).frame(width: 80)
                    Text("\(Int(state.fontSize))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6)).frame(width: 24)
                }
                Divider().frame(height: 16).background(Color.white.opacity(0.3))
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: $state.scrollSpeed, in: 10...100, step: 5)
                        .tint(.white).frame(width: 80)
                    Text("\(Int(state.scrollSpeed))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6)).frame(width: 24)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.5)))

            Button { state.showEditor = true } label: {
                Label("Edit Script", systemImage: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
    }
}

// MARK: - PiP Preview

struct PiPPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CinematicCameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let layer = cameraManager.previewLayer
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.layer.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }
                .forEach { $0.frame = uiView.bounds }
        }
    }
}

// MARK: - Script Editor Sheet

struct TeleprompterEditorSheet: View {
    @ObservedObject var state: TeleprompterState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $state.script)
                    .font(.system(size: 17))
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .frame(maxHeight: .infinity)
            }
            .padding()
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { state.resetScroll(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
