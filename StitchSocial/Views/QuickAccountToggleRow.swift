//
//  QuickAccountToggleRow.swift
//  StitchSocial
//
//  Single-tap toggle row that lives inside Settings → Accounts. When the
//  user has two linked accounts (one personal, one business), this row
//  shows the OTHER account and one-tap swaps to it. When only one is
//  linked, it shows nothing — the "Manage linked accounts" entry is the
//  path to add the second.
//

import SwiftUI
import FirebaseAuth

struct QuickAccountToggleRow: View {

    @ObservedObject private var manager = LinkedAccountManager.shared
    @State private var isSwitching = false
    @State private var error: String?

    var body: some View {
        // Only render when there's a meaningful "other" account to swap to.
        if let other = manager.otherAccount(), manager.accounts.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.cyan)
                        .frame(width: 36, height: 36)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch to \(other.accountType.displayName)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(other.displayName.isEmpty ? other.email : other.displayName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    if isSwitching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.cyan)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await toggle() }
                }

                if let error = error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.leading, 48)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func toggle() async {
        guard !isSwitching else { return }
        isSwitching = true
        error = nil
        defer { isSwitching = false }
        do {
            try await manager.toggleActive()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
