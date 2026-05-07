//
//  AccountSwitcherView.swift
//  StitchSocial
//
//  Settings-mounted sheet that lists linked accounts (personal + business),
//  lets the user toggle between them without re-entering credentials, and
//  surfaces an "Add the other type" CTA when only one is linked.
//
//  Caveats:
//   • Max 2 linked accounts on this device (1 personal + 1 business).
//   • Both accounts must use different emails (Firebase Auth requires it).
//   • Local-only — adding an account on iPhone doesn't auto-show on iPad.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AccountSwitcherView: View {

    @ObservedObject private var manager = LinkedAccountManager.shared
    @EnvironmentObject var authService: AuthService

    @Environment(\.dismiss) private var dismiss

    @State private var isSwitching = false
    @State private var error: String?
    @State private var addSheet: AddSheetMode?
    @State private var pendingRemove: LinkedAccount?

    private enum AddSheetMode: Identifiable {
        case create(AccountType)
        case linkExisting(AccountType)
        case picker(AccountType)
        var id: String {
            switch self {
            case .create(let t): return "create_\(t.rawValue)"
            case .linkExisting(let t): return "link_\(t.rawValue)"
            case .picker(let t): return "picker_\(t.rawValue)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if manager.accounts.isEmpty {
                        currentSessionRow
                    } else {
                        ForEach(manager.accounts) { account in
                            accountRow(account)
                        }
                    }

                    if let missing = missingAccountType {
                        addAccountCTA(for: missing)
                            .padding(.top, 12)
                    }

                    if let error = error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .padding(.top, 8)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Color.black)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
            .alert(item: Binding(
                get: { pendingRemove },
                set: { pendingRemove = $0 }
            )) { account in
                Alert(
                    title: Text("Remove linked account?"),
                    message: Text("\(account.displayName) will no longer appear here. The account itself isn't deleted."),
                    primaryButton: .destructive(Text("Remove")) {
                        manager.removeAccount(uid: account.uid)
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(item: $addSheet) { mode in
                switch mode {
                case .picker(let type):
                    AddAccountPickerSheet(targetType: type) { choice in
                        addSheet = nil
                        // Re-open the picked flow on the next runloop tick
                        // so the sheet swap is clean.
                        DispatchQueue.main.async {
                            switch choice {
                            case .create:       addSheet = .create(type)
                            case .linkExisting: addSheet = .linkExisting(type)
                            }
                        }
                    }
                case .create(let type):
                    CreateLinkedAccountView(targetType: type) { result in
                        addSheet = nil
                        handleAddResult(result)
                    }
                case .linkExisting(let type):
                    LinkExistingAccountView(targetType: type) { result in
                        addSheet = nil
                        handleAddResult(result)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Rows

    private var currentSessionRow: some View {
        // Shown only when LinkedAccountManager hasn't seen the active
        // account yet (e.g. first launch after the feature ships). It
        // explains why the list is empty and lets them seed the active
        // account into the manager — handy on existing installs.
        VStack(alignment: .leading, spacing: 12) {
            Text("Your current account isn't linked yet.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text("Linking lets you toggle between this account and another type without signing in each time.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func accountRow(_ account: LinkedAccount) -> some View {
        let isActive = manager.activeUID == account.uid
        return HStack(spacing: 12) {
            Avatar(account: account)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    AccountTypePill(type: account.accountType)
                    Text(account.email)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 18))
            } else if isSwitching {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await switchTo(account) }
                } label: {
                    Text("Switch")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Menu {
                Button(role: .destructive) {
                    pendingRemove = account
                } label: {
                    Label("Remove from this device", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func addAccountCTA(for type: AccountType) -> some View {
        Button {
            addSheet = .picker(type)
        } label: {
            HStack {
                Image(systemName: type == .business ? "building.2.fill" : "person.fill")
                    .foregroundColor(.cyan)
                Text("Add \(type.displayName) Account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .background(Color.cyan.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Helpers

    /// Returns the AccountType that's NOT yet linked, or nil if both are.
    private var missingAccountType: AccountType? {
        if manager.accounts.count >= 2 { return nil }
        let linked = Set(manager.accounts.map { $0.accountType })
        if !linked.contains(.personal) && !linked.contains(.business) {
            // Empty list — propose adding the type opposite to the
            // currently signed-in account, if we know it.
            let currentType = authService.currentUser?.accountType
            if currentType == .personal { return .business }
            if currentType == .business { return .personal }
            return .business
        }
        if !linked.contains(.business) { return .business }
        if !linked.contains(.personal) { return .personal }
        return nil
    }

    private func switchTo(_ account: LinkedAccount) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await manager.switchTo(uid: account.uid)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleAddResult(_ result: AddAccountResult) {
        switch result {
        case .added:
            self.error = nil
        case .failed(let message):
            self.error = message
        case .cancelled:
            break
        }
    }
}

// MARK: - Pill / Avatar

private struct AccountTypePill: View {
    let type: AccountType
    var body: some View {
        Text(type.displayName.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundColor(type == .business ? .orange : .cyan)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((type == .business ? Color.orange : Color.cyan).opacity(0.15))
            .clipShape(Capsule())
    }
}

private struct Avatar: View {
    let account: LinkedAccount
    var body: some View {
        AsyncImage(url: account.profileImageURL.flatMap { URL(string: $0) }) { img in
            img.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Text(String(account.displayName.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(0.1))
        .clipShape(Circle())
    }
}

// MARK: - Add-flow API surface (implementations live in AddLinkedAccountFlow.swift)

enum AddAccountResult {
    case added(LinkedAccount)
    case failed(String)
    case cancelled
}

enum AddAccountChoice {
    case create
    case linkExisting
}

private struct AddAccountPickerSheet: View {
    let targetType: AccountType
    let onChoose: (AddAccountChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add a \(targetType.displayName.lowercased()) account")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 24)

                Text(targetType == .business
                     ? "Business accounts post brand content and run ads. They can't hype, follow communities, or earn clout."
                     : "Personal accounts post videos, follow others, and earn clout.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("⚠️ Must use a different email than your current account.")
                    .font(.system(size: 12))
                    .foregroundColor(.orange.opacity(0.85))
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Button { onChoose(.create) } label: {
                        AddOptionRow(icon: "plus.circle.fill",
                                     title: "Create New Account",
                                     subtitle: "Start fresh with a new email")
                    }
                    Button { onChoose(.linkExisting) } label: {
                        AddOptionRow(icon: "link",
                                     title: "Link Existing Account",
                                     subtitle: "Use credentials from another Stitch account")
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        .presentationDetents([.height(360)])
        .preferredColorScheme(.dark)
    }
}

private struct AddOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.cyan)
                .frame(width: 36, height: 36)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
