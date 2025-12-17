//
//  CustomVideoPlayerView.swift
//  StitchSocial
//
//  Direct AVPlayerLayer implementation for guaranteed video rendering
//

import SwiftUI
import AVFoundation
import UIKit

struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }
    
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }
}

final class PlayerLayerView: UIView {
    
    private var playerLayer: AVPlayerLayer?
    
    var player: AVPlayer? {
        didSet {
            if player !== oldValue {
                setupPlayerLayer()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
    
    private func setupPlayerLayer() {
        // Remove old layer
        playerLayer?.removeFromSuperlayer()
        
        guard let player = player else { return }
        
        // Create new layer
        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = UIColor.black.cgColor
        
        self.layer.addSublayer(layer)
        self.playerLayer = layer
        
        print("🎥 CUSTOM PLAYER VIEW: Layer setup complete")
    }
}
