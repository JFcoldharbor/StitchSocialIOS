//
//  CustomVideoPlayerView.swift
//  StitchSocial
//
//  Direct AVPlayerLayer implementation for guaranteed video rendering
//  FIXED: Transparent background until first frame renders (no black flash)
//  Uses AVPlayerLayer.isReadyForDisplay KVO for precise frame-ready signal
//

import SwiftUI
import AVFoundation
import UIKit

struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    var onReadyForDisplay: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.onReadyForDisplay = onReadyForDisplay
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.onReadyForDisplay = onReadyForDisplay
        if uiView.player !== player {
            uiView.player = player
        }
    }
}

final class PlayerLayerView: UIView {
    
    private var playerLayer: AVPlayerLayer?
    private var readyObservation: NSKeyValueObservation?
    var onReadyForDisplay: (() -> Void)?
    
    var player: AVPlayer? {
        didSet {
            if player !== oldValue {
                setupPlayerLayer()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    private func setupPlayerLayer() {
        readyObservation?.invalidate()
        readyObservation = nil
        playerLayer?.removeFromSuperlayer()
        
        guard let player = player else { return }
        
        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = UIColor.clear.cgColor
        
        self.layer.addSublayer(layer)
        self.playerLayer = layer
        
        if layer.isReadyForDisplay {
            onReadyForDisplay?()
        } else {
            readyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    DispatchQueue.main.async {
                        self?.onReadyForDisplay?()
                    }
                    self?.readyObservation?.invalidate()
                    self?.readyObservation = nil
                }
            }
        }
    }
    
    deinit {
        readyObservation?.invalidate()
    }
}
