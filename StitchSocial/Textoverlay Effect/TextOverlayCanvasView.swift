//
//  TextOverlayEditorView.swift
//  StitchSocial
//
//  Instagram-style inline text editing.
//  - Tap canvas → new sticker + keyboard opens immediately
//  - Tap sticker → edit in place, keyboard + floating controls appear
//  - Floating multi-row bar sits above keyboard (not inside keyboard toolbar)
//  - Row 1: Done · Delete · Bold · Size- · Size+
//  - Row 2: Style chips (Bold Pill / Outline / Neon / Typewriter / Gradient)
//  - Row 3: Font chips
//  - Row 4: Text color dots · BG color dots

import SwiftUI

// MARK: - Canvas

struct TextOverlayCanvasView: View {
    @ObservedObject var editState: VideoEditStateManager
    @Binding var selectedOverlayID: UUID?
    @Binding var editingOverlayID: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Tap empty → create sticker at position
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { location in
                        if editingOverlayID != nil {
                            // Tap away → commit current edit
                            editingOverlayID = nil
                            selectedOverlayID = nil
                        } else {
                            createSticker(at: location, in: geo)
                        }
                    }

                ForEach(editState.state.textOverlays) { overlay in
                    stickerView(overlay: overlay, geo: geo)
                }
            }
        }
    }

    // MARK: - Single Sticker

    @ViewBuilder
    private func stickerView(overlay: TextOverlay, geo: GeometryProxy) -> some View {
        let isEditing  = editingOverlayID == overlay.id
        let isSelected = selectedOverlayID == overlay.id

        ZStack {
            if isEditing {
                InlineOverlayEditor(
                    overlay: Binding(
                        get: { editState.state.textOverlays.first { $0.id == overlay.id } ?? overlay },
                        set: { updated in editState.updateOverlay(id: overlay.id) { o in o = updated } }
                    ),
                    onCommit: {
                        let current = editState.state.textOverlays.first { $0.id == overlay.id }
                        if current?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                            editState.removeOverlay(id: overlay.id)
                            selectedOverlayID = nil
                        }
                        editingOverlayID = nil
                    }
                )
            } else {
                TextStickerView(overlay: overlay, isSelected: isSelected)
                    .gesture(dragGesture(for: overlay, in: geo))
                    .simultaneousGesture(magnifyGesture(for: overlay))
                    .simultaneousGesture(rotateGesture(for: overlay))
                    .onTapGesture {
                        selectedOverlayID = overlay.id
                        editingOverlayID  = overlay.id
                    }
                    // Selection ring
                    .overlay(
                        isSelected && !isEditing
                        ? AnyView(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            .padding(-6))
                        : AnyView(EmptyView())
                    )
            }
        }
        .position(
            x: overlay.normalizedX * geo.size.width,
            y: overlay.normalizedY * geo.size.height
        )
    }

    // MARK: - Create

    private func createSticker(at location: CGPoint, in geo: GeometryProxy) {
        var new = TextOverlay(text: "", style: .boldPill)
        new.font = .futura
        new.normalizedX = min(max(location.x / geo.size.width,  0.1), 0.9)
        new.normalizedY = min(max(location.y / geo.size.height, 0.1), 0.9)
        editState.addOverlay(new)
        selectedOverlayID = new.id
        editingOverlayID  = new.id
    }

    // MARK: - Gestures

    private func dragGesture(for overlay: TextOverlay, in geo: GeometryProxy) -> some Gesture {
        let mgr = editState; let oid = overlay.id
        return DragGesture(minimumDistance: 4).onChanged { v in
            mgr.updateOverlay(id: oid) { o in
                o.normalizedX = min(max(v.location.x / geo.size.width,  0.05), 0.95)
                o.normalizedY = min(max(v.location.y / geo.size.height, 0.05), 0.95)
            }
        }
    }
    private func magnifyGesture(for overlay: TextOverlay) -> some Gesture {
        let mgr = editState; let oid = overlay.id; let s = overlay.scale
        return MagnifyGesture().onChanged { v in
            mgr.updateOverlay(id: oid) { o in o.scale = min(max(s * v.magnification, 0.4), 4.0) }
        }
    }
    private func rotateGesture(for overlay: TextOverlay) -> some Gesture {
        let mgr = editState; let oid = overlay.id; let r = overlay.rotation
        return RotateGesture().onChanged { v in
            mgr.updateOverlay(id: oid) { o in o.rotation = r + v.rotation.degrees }
        }
    }
}

// MARK: - Inline Editor (with persistent floating toolbar)

struct InlineOverlayEditor: View {
    @Binding var overlay: TextOverlay
    let onCommit: () -> Void
    @FocusState private var focused: Bool
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        ZStack {
            // Live sticker preview — updates as user types
            TextStickerView(overlay: overlay, isSelected: true)
                .allowsHitTesting(false)

            // Transparent text field — owns the keyboard
            TextField("", text: $overlay.text, axis: .vertical)
                .focused($focused)
                .opacity(0.001)
                .frame(
                    width: max(overlay.fontSize * CGFloat(max(overlay.text.count, 4)) * 0.55, 80),
                    height: overlay.fontSize * 1.8
                )
                .multilineTextAlignment(.center)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
            observeKeyboard()
        }
        .onDisappear { onCommit() }
        .onChange(of: focused) { _, isFocused in if !isFocused { onCommit() } }
        // Floating control bar sits above keyboard
        .overlay(alignment: .bottom) {
            if keyboardHeight > 0 {
                FloatingTextControls(overlay: $overlay, onDone: {
                    focused = false
                }, onDelete: {
                    overlay.text = ""
                    focused = false
                })
                .offset(y: -(keyboardHeight))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: keyboardHeight)
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil, queue: .main
        ) { n in
            let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
            withAnimation { keyboardHeight = frame.height }
        }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main
        ) { _ in withAnimation { keyboardHeight = 0 } }
    }
}

// MARK: - Floating Text Controls

struct FloatingTextControls: View {
    @Binding var overlay: TextOverlay
    let onDone: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Row 1: Actions + Bold + Size ──────────────────────────
            HStack(spacing: 0) {
                // Done
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white))
                }
                .padding(.leading, 12)

                Spacer()

                // Bold
                Button { overlay.isBold.toggle() } label: {
                    Text("B")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(overlay.isBold ? .black : .white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(overlay.isBold ? Color.white : Color.white.opacity(0.15)))
                }

                // Size −
                Button { overlay.fontSize = max(14, overlay.fontSize - 2) } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }

                // Size +
                Button { overlay.fontSize = min(60, overlay.fontSize + 2) } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .padding(.trailing, 12)
            }
            .padding(.vertical, 8)

            thinDivider

            // ── Row 2: Style chips ─────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TextOverlayStyle.allCases, id: \.rawValue) { style in
                        Button { overlay.applyStyle(style) } label: {
                            Text(style.rawValue)
                                .font(.system(size: 12, weight: overlay.style == style ? .bold : .medium))
                                .foregroundColor(overlay.style == style ? .black : .white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(
                                    overlay.style == style ? Color.white : Color.white.opacity(0.15)
                                ))
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 38)

            thinDivider

            // ── Row 3: Font chips ──────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(OverlayFont.allCases, id: \.rawValue) { f in
                        Button { overlay.font = f } label: {
                            Text(f.label)
                                .font(f.swiftUIFont(size: 13, bold: overlay.font == f))
                                .foregroundColor(overlay.font == f ? .black : .white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(
                                    overlay.font == f ? Color.white : Color.white.opacity(0.15)
                                ))
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 38)

            thinDivider

            // ── Row 4: Text color + BG color ───────────────────────────
            HStack(spacing: 0) {
                // Text colors
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Label("", systemImage: "character")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .labelStyle(.iconOnly)
                        ForEach(TextOverlayPalette.textColors.indices, id: \.self) { i in
                            let c = TextOverlayPalette.textColors[i]
                            colorDot(c, isText: true)
                        }
                        Divider().frame(height: 20).padding(.horizontal, 4)
                        Label("", systemImage: "rectangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .labelStyle(.iconOnly)
                        ForEach(TextOverlayPalette.bgColors.indices, id: \.self) { i in
                            let c = TextOverlayPalette.bgColors[i]
                            colorDot(c, isText: false)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .frame(height: 38)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.black.opacity(0.4)))
                .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        )
    }

    private func colorDot(_ c: Color, isText: Bool) -> some View {
        let uic = UIColor(c)
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; var a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)

        let isSelected: Bool = isText
            ? (abs(overlay.textColorRed - r) < 0.05 && abs(overlay.textColorGreen - g) < 0.05)
            : (abs(overlay.bgColorRed - r) < 0.05 && abs(overlay.bgColorGreen - g) < 0.05)

        return Circle()
            .fill(c)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(
                isSelected ? Color.white : Color.white.opacity(0.2),
                lineWidth: isSelected ? 2.5 : 1
            ))
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .onTapGesture {
                if isText { overlay.setTextColor(c) }
                else       { overlay.setBgColor(c)  }
            }
            .animation(.spring(response: 0.2), value: isSelected)
    }

    private var thinDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

// MARK: - Panel (right-rail text tab)

struct TextOverlayPanelView: View {
    @ObservedObject var editState: VideoEditStateManager
    @Binding var selectedOverlayID: UUID?
    @Binding var editingOverlayID: UUID?

    var body: some View {
        VStack(spacing: 14) {
            // Add text button
            Button {
                var new = TextOverlay(text: "", style: .boldPill)
                new.font = .futura
                new.normalizedX = 0.5
                new.normalizedY = 0.4
                editState.addOverlay(new)
                selectedOverlayID = new.id
                editingOverlayID  = new.id
            } label: {
                HStack(spacing: 8) {
                    Text("Aa")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Add Text")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color.cyan.opacity(0.85), Color.blue.opacity(0.75)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                )
                .padding(.horizontal, 16)
            }

            // Hint when no overlays
            if editState.state.textOverlays.isEmpty {
                Text("Tap anywhere on the video to place text")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            } else {
                // Sticker chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(editState.state.textOverlays) { overlay in
                            chip(overlay)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func chip(_ overlay: TextOverlay) -> some View {
        let isActive = selectedOverlayID == overlay.id
        return HStack(spacing: 6) {
            // Color dot
            Circle()
                .fill(Color(overlay.textColor))
                .frame(width: 8, height: 8)
            Text(overlay.text.isEmpty ? "empty" : String(overlay.text.prefix(16)))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(overlay.text.isEmpty ? .white.opacity(0.3) : .white)
                .lineLimit(1)
            Button {
                editState.removeOverlay(id: overlay.id)
                if selectedOverlayID == overlay.id { selectedOverlayID = nil }
                if editingOverlayID  == overlay.id { editingOverlayID  = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            Capsule().fill(isActive ? Color.cyan.opacity(0.3) : Color.white.opacity(0.1))
        )
        .overlay(Capsule().stroke(isActive ? Color.cyan.opacity(0.6) : Color.clear, lineWidth: 1))
        .onTapGesture {
            selectedOverlayID = overlay.id
            editingOverlayID  = overlay.id
        }
    }
}
