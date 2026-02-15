//
//  CameraPreviewView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/14/26.
//


//
//  StreamVideoComponents.swift
//  StitchSocial
//
//  Layer 8: Views - Camera + Video Player components for stream video replies
//  Extracted from LiveStreamViewerView to keep AVFoundation imports clean.
//

import Foundation
import SwiftUI
import AVFoundation

// MARK: - Notification Names for Camera Control

extension Notification.Name {
    static let startVideoRecording = Notification.Name("startVideoRecording")
    static let stopVideoRecording = Notification.Name("stopVideoRecording")
    static let videoRecordingComplete = Notification.Name("videoRecordingComplete")
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let useFrontCamera: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = CameraSessionView()
        view.setupSession(useFront: useFrontCamera)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let camView = uiView as? CameraSessionView {
            camView.switchCamera(useFront: useFrontCamera)
        }
    }
}

class CameraSessionView: UIView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var recordingDelegate = RecordingDelegate()
    
    func setupSession(useFront: Bool) {
        session.sessionPreset = .high
        
        let position: AVCaptureDevice.Position = useFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        if session.canAddInput(input) { session.addInput(input) }
        currentInput = input
        
        // Audio
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        previewLayer = preview
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(startRecording), name: .startVideoRecording, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: .stopVideoRecording, object: nil)
    }
    
    func switchCamera(useFront: Bool) {
        let position: AVCaptureDevice.Position = useFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.beginConfiguration()
        if let old = currentInput { session.removeInput(old) }
        if session.canAddInput(newInput) { session.addInput(newInput) }
        currentInput = newInput
        session.commitConfiguration()
    }
    
    @objc private func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("reply_\(UUID().uuidString).mp4")
        movieOutput.startRecording(to: tempURL, recordingDelegate: recordingDelegate)
    }
    
    @objc private func stopRecording() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    deinit {
        session.stopRunning()
        NotificationCenter.default.removeObserver(self)
    }
}

class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        NotificationCenter.default.post(name: .videoRecordingComplete, object: outputFileURL)
    }
}

// MARK: - Video Preview Player (for review after recording)

struct VideoPreviewPlayer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> UIView {
        VideoPlayerUIView(url: url)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}

class VideoPlayerUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    init(url: URL) {
        super.init(frame: .zero)
        player = AVPlayer(url: url)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        playerLayer = layer
        player?.play()
        
        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    deinit {
        player?.pause()
        NotificationCenter.default.removeObserver(self)
    }
}