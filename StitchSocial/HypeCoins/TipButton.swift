//
//  TipButton.swift
//  StitchSocial
//
//  Tip button for ContextualVideoOverlay swappable slot.
//  Uses HypeCoinView as icon. Tap = 1 coin. Long press = 5 coins.
//  Mirrors ProgressiveHypeButton exactly — same count display, same FloatingIconManager pattern.
//
//  CACHING: Delegates balance checks to TipService.shared. No reads here.
//

import SwiftUI

struct TipButton: View {

    let videoID: String
    let creatorID: String
    let currentUserID: String
    let currentTipCount: Int              // total tips this video has received (from Firestore)

    @ObservedObject var iconManager: FloatingIconManager
    @ObservedObject private var tipService = TipService.shared

    @State private var isPressed = false
    @State private var buttonPosition: CGPoint = .zero
    @State private var showingBurst = false
    @State private var pulsePhase: Double = 0
    @State private var errorMessage: String = ""
    @State private var showingError = false

    // MARK: - Computed

    private var isSelfTip: Bool { currentUserID == creatorID }
    private var hasBalance: Bool {
        guard tipService.balanceLoaded else { return true }
        return tipService.localCoinBalance >= TipConfig.minimumBalanceRequired
    }
    private var isDisabled: Bool { isSelfTip || !hasBalance }
    private var sessionTotal: Int { tipService.sessionTotal(for: videoID) }

    // Display: session total added on top of persisted count
    private var displayCount: Int { currentTipCount + sessionTotal }

    // MARK: - Body

    var body: some View {
        ZStack {
            buttonBase
            coinIcon
            tipCountDisplay

            if isSelfTip { selfTipOverlay }
            if showingBurst { burstRing }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .rotation3DEffect(.degrees(isPressed ? 5 : 0), axis: (x: 1, y: 0, z: 0))
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .opacity(isDisabled ? 0.5 : 1.0)
        // Use simultaneousGesture so tap fires even when long press is recognized.
        // onTapGesture + onLongPressGesture stacked alone causes the long press to
        // swallow taps — SwiftUI waits for the long press threshold before resolving.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: TipConfig.longPressDuration)
                .onChanged { pressing in
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPressed = pressing
                        showingBurst = pressing
                    }
                }
                .onEnded { _ in
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isPressed = false
                        showingBurst = false
                    }
                    handleTap(isLong: true)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    guard !isDisabled else { return }
                    handleTap(isLong: false)
                }
        )
        .disabled(isDisabled)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    buttonPosition = CGPoint(
                        x: geo.frame(in: .global).midX,
                        y: geo.frame(in: .global).midY
                    )
                }
            }
        )
        .overlay(errorOverlay)
        .onAppear { startPulse() }
        .onDisappear { TipService.shared.clearState(videoID: videoID) }
    }

    // MARK: - Components

    private var buttonBase: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { layer in
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.black.opacity(0.1), Color.black.opacity(0.3)],
                        center: .center, startRadius: 0, endRadius: 25
                    ))
                    .frame(width: 42, height: 42)
                    .offset(x: CGFloat(layer) * 1.5, y: CGFloat(layer) * 1.5)
                    .opacity(0.4 - Double(layer) * 0.1)
            }

            Circle()
                .fill(RadialGradient(
                    colors: isSelfTip
                        ? [Color.gray.opacity(0.4), Color.black.opacity(0.7), Color.black.opacity(0.9)]
                        : [Color.black.opacity(0.4), Color.black.opacity(0.7), Color.black.opacity(0.9)],
                    center: .topLeading, startRadius: 0, endRadius: 30
                ))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: isSelfTip
                                ? [.gray, .gray.opacity(0.6)]
                                : showingBurst
                                    ? [StitchColors.tipGoldLight, StitchColors.tipGold, .orange]
                                    : [StitchColors.tipGold.opacity(0.6), .orange.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: showingBurst ? 3.0 : 1.5
                    )
                    .opacity(0.8 + sin(pulsePhase) * 0.2)
                )
                .shadow(
                    color: isSelfTip ? .gray.opacity(0.3)
                        : showingBurst ? StitchColors.tipGold.opacity(0.6)
                        : StitchColors.tipGold.opacity(0.3),
                    radius: 4, x: 0, y: 2
                )
        }
    }

    private var coinIcon: some View {
        HypeCoinView(size: 26)
            .scaleEffect(isSelfTip ? 1.0 : showingBurst ? 1.3 : (1.0 + sin(pulsePhase * 2) * 0.08))
            .shadow(color: isSelfTip ? .gray : StitchColors.tipGold, radius: 6)
    }

    /// Matches hypeCountDisplay offset exactly
    private var tipCountDisplay: some View {
        Text("\(displayCount)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
            .offset(y: -35)
    }

    private var selfTipOverlay: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.3)).frame(width: 50, height: 50)
                .overlay(Circle().stroke(Color.gray, lineWidth: 2))
            Image(systemName: "person.fill.xmark")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.gray)
                .shadow(color: .black, radius: 1, x: 0.5, y: 0.5)
        }.scaleEffect(1.1)
    }

    private var burstRing: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [StitchColors.tipGoldLight, StitchColors.tipGold, .orange, StitchColors.tipGold, StitchColors.tipGoldLight],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(pulsePhase * 20))

            Text("x5")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(StitchColors.tipGold)
                .offset(y: 30)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var errorOverlay: some View {
        Group {
            if showingError {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .offset(y: -60)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func handleTap(isLong: Bool) {
        guard !isDisabled else {
            showError(isSelfTip ? TipConfig.selfTipErrorMessage : TipConfig.insufficientFundsMessage)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let amount = isLong ? TipConfig.longPressAmount : TipConfig.singleTapAmount

        withAnimation(.spring(response: 0.1, dampingFraction: 0.6)) { isPressed = true }

        UIImpactFeedbackGenerator(style: isLong ? .heavy : .medium).impactOccurred()

        // Floating coin icon — proper tip type with gold coin animation
        iconManager.spawnTipIcon(
            from: buttonPosition,
            userTier: .rookie,
            isLongPress: isLong
        )

        TipService.shared.handleTap(
            videoID: videoID,
            tipperID: currentUserID,
            creatorID: creatorID,
            amount: amount
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { isPressed = false }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showingError = false }
        }
    }

    private func startPulse() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            pulsePhase += 0.2
        }
    }
}
