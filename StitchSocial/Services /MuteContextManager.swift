//
//  MuteContextManager.swift
//  StitchSocial
//
//  Global mute state manager with:
//  - Persistent state (UserDefaults)
//  - Phone call detection (CallKit)
//  - Volume button listening (AVAudioSession)
//  - Auto-mute during calls
//  - Single source of truth for all views
//

import SwiftUI
import AVFoundation
import CallKit

class MuteContextManager: ObservableObject {
    static let shared = MuteContextManager()
    
    @Published var isMuted: Bool {
        didSet {
            // Persist to UserDefaults whenever it changes
            UserDefaults.standard.set(isMuted, forKey: "StitchSocial_isMuted")
            print("🔊 MUTE: isMuted = \(isMuted)")
        }
    }
    
    @Published var isOnCall: Bool = false
    
    private var audioSession: AVAudioSession
    private var callObserver: CXCallObserver
    private var volumeObserver: NSObjectProtocol?
    private var lastToggleTime: Date = Date.distantPast  // Debounce rapid toggles
    private var lastVolumeButtonTime: Date = Date.distantPast  // Debounce volume button presses
    
    private init() {
        self.audioSession = AVAudioSession.sharedInstance()
        self.callObserver = CXCallObserver()
        
        // Load persisted mute state (default to true = muted)
        let savedMuteState = UserDefaults.standard.object(forKey: "StitchSocial_isMuted") as? Bool ?? true
        self.isMuted = savedMuteState
        
        print("🔊 MUTE: Initialized with isMuted = \(savedMuteState)")
        
        setupCallDetection()
        setupVolumeButtonListening()
    }
    
    // MARK: - Phone Call Detection (CallKit)
    
    private func setupCallDetection() {
        // Check initial call state
        updateCallState()
        
        // Monitor call state periodically (every 0.5 seconds)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateCallState()
        }
    }
    
    private func updateCallState() {
        let calls = callObserver.calls
        let wasOnCall = isOnCall
        isOnCall = !calls.isEmpty
        
        // If call just started, force mute
        if isOnCall && !wasOnCall {
            print("☎️ MUTE: Call started - forcing mute ON")
            isMuted = true
        }
        
        // If call just ended, restore previous state
        if !isOnCall && wasOnCall {
            print("☎️ MUTE: Call ended - user can unmute if desired")
        }
    }
    
    // MARK: - Volume Button Listening (AVAudioSession)
    
    private func setupVolumeButtonListening() {
        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Start monitoring volume level changes with a timer
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                let currentVolume = self?.audioSession.outputVolume ?? 0
                // If volume is above threshold, user likely pressed volume up
                if currentVolume > 0.8 {
                    self?.handleVolumeButtonPress()
                }
            }
            
            print("🔊 MUTE: Volume button listening enabled")
        } catch {
            print("❌ MUTE: Failed to setup volume button listening: \(error)")
        }
    }
    
    private func handleVolumeButtonPress() {
        // Debounce: ignore volume button presses within 1 second
        let timeSinceLastPress = Date().timeIntervalSince(lastVolumeButtonTime)
        guard timeSinceLastPress > 1.0 else { return }
        
        // Get current volume level
        let volume = audioSession.outputVolume
        
        // Volume UP detected (higher than typical playback volume)
        if volume > 0.7 {
            // Only unmute (volume UP unmutes only)
            if isMuted && !isOnCall {
                lastVolumeButtonTime = Date()
                DispatchQueue.main.async {
                    print("🔊 MUTE: Volume UP pressed - unmuting")
                    self.isMuted = false
                }
            }
        }
        // Volume DOWN doesn't do anything in this implementation
        // User must tap button to mute
    }
    
    // MARK: - Public Methods
    
    func mute() {
        isMuted = true
    }
    
    func unmute() {
        // Can't unmute during a call
        guard !isOnCall else {
            print("⚠️ MUTE: Cannot unmute during phone call")
            return
        }
        isMuted = false
    }
    
    func toggle() {
        // Debounce: ignore toggles within 0.3 seconds of last toggle
        let timeSinceLastToggle = Date().timeIntervalSince(lastToggleTime)
        guard timeSinceLastToggle > 0.3 else {
            print("🔊 MUTE: Toggle ignored (debounce active)")
            return
        }
        
        lastToggleTime = Date()
        
        if isMuted && !isOnCall {
            unmute()
        } else if !isMuted {
            mute()
        }
    }
    
    deinit {
        if let observer = volumeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - Mute Button View

struct MuteButton: View {
    @EnvironmentObject var muteManager: MuteContextManager
    
    var body: some View {
        // Only show when muted
        if muteManager.isMuted {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    muteManager.unmute()
                }
            }) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
            }
            .transition(.opacity.combined(with: .scale))
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MuteContextManager_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Mute Manager Demo")
                .font(.headline)
            
            MuteButton()
                .environmentObject(MuteContextManager.shared)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Muted: \(MuteContextManager.shared.isMuted ? "Yes 🔇" : "No 🔊")")
                Text("On Call: \(MuteContextManager.shared.isOnCall ? "Yes" : "No")")
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding()
    }
}
#endif
