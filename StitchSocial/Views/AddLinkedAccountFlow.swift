//
//  AddLinkedAccountFlow.swift
//  StitchSocial
//
//  Two-flow add-account UI for the multi-account toggle:
//
//   • CreateLinkedAccountView   → signUp + register with LinkedAccountManager
//   • LinkExistingAccountView   → signIn + verify accountType matches the
//                                  slot being filled, then register
//
//  Both run "off-session" — they sign in/up the *new* account, capture the
//  Auth credential, register it with LinkedAccountManager, then sign back
//  into the previously-active account so the user stays where they were.
//  The toggle UI in AccountSwitcherView is what actually flips to the new
//  one when the user wants to use it.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Create New Account

struct CreateLinkedAccountView: View {

    let targetType: AccountType
    let onComplete: (AddAccountResult) -> Void

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var brandName = ""
    @State private var websiteURL = ""
    @State private var businessCategory: AdCategory = .other

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    field("Email", binding: $email, kind: .email)
                    field("Password (8+ chars)", binding: $password, kind: .password)

                    if targetType == .personal {
                        field("Display name", binding: $displayName)
                    } else {
                        field("Brand name", binding: $brandName)
                        field("Website (optional)", binding: $websiteURL, kind: .url)
                        categoryPicker
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    submitButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.black)
            .navigationTitle("New \(targetType.displayName) Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onComplete(.cancelled)
                        dismiss()
                    }.foregroundColor(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: targetType == .business ? "building.2.fill" : "person.fill")
                .font(.system(size: 28))
                .foregroundColor(.cyan)
            Text(targetType == .business
                 ? "Brand identity for ads, promos, and influencer collabs."
                 : "Standard creator account — post, follow, earn clout.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
    }

    private var categoryPicker: some View {
        HStack {
            Text("Category").foregroundColor(.white.opacity(0.7)).font(.system(size: 13))
            Spacer()
            Picker("", selection: $businessCategory) {
                ForEach(AdCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .tint(.cyan)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var submitButton: some View {
        Button {
            Task { await create() }
        } label: {
            HStack {
                if isWorking { ProgressView().controlSize(.small).tint(.black) }
                Text(isWorking ? "Creating…" : "Create \(targetType.displayName) Account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Color.cyan : Color.cyan.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSubmit || isWorking)
        .padding(.top, 12)
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 8 else { return false }
        if targetType == .business { return !brandName.isEmpty }
        return !displayName.isEmpty
    }

    // MARK: - Create

    private func create() async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        // We capture the previously-active account so we can restore it
        // after signing up the new account (which Firebase makes "current"
        // automatically). The user shouldn't lose their session just by
        // adding a second account.
        let previousActiveUID = Auth.auth().currentUser?.uid

        do {
            let user: BasicUserInfo
            if targetType == .business {
                user = try await authService.signUp(
                    email: email,
                    password: password,
                    username: nil,
                    displayName: brandName,
                    accountType: .business,
                    brandName: brandName,
                    websiteURL: websiteURL.isEmpty ? nil : websiteURL,
                    businessCategory: businessCategory
                )
            } else {
                user = try await authService.signUp(
                    email: email,
                    password: password,
                    username: nil,
                    displayName: displayName,
                    accountType: .personal
                )
            }

            // Register the new account with LinkedAccountManager. Saves
            // email+password to Keychain so the toggle works without
            // re-prompting later.
            let linked = LinkedAccount(
                uid: user.id,
                email: email,
                accountType: user.accountType,
                displayName: user.displayName,
                profileImageURL: user.profileImageURL,
                provider: .emailPassword,
                addedAt: Date()
            )
            try LinkedAccountManager.shared.addEmailPasswordAccount(
                linked,
                email: email,
                password: password
            )

            // Restore the previous session so the user stays where they
            // were. If there's no previous session (first add ever), keep
            // the new account active.
            if let prevUID = previousActiveUID, prevUID != user.id {
                try await LinkedAccountManager.shared.switchTo(uid: prevUID)
            }

            onComplete(.added(linked))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Best-effort restore previous session on failure.
            if let prevUID = previousActiveUID,
               Auth.auth().currentUser?.uid != prevUID,
               LinkedAccountManager.shared.accounts.contains(where: { $0.uid == prevUID }) {
                try? await LinkedAccountManager.shared.switchTo(uid: prevUID)
            }
        }
    }

    private enum FieldKind { case plain, email, password, url }

    @ViewBuilder
    private func field(_ placeholder: String, binding: Binding<String>, kind: FieldKind = .plain) -> some View {
        Group {
            switch kind {
            case .password:
                SecureField(placeholder, text: binding)
            case .email:
                TextField(placeholder, text: binding)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .url:
                TextField(placeholder, text: binding)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .plain:
                TextField(placeholder, text: binding)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundColor(.white)
    }
}

// MARK: - Link Existing Account

struct LinkExistingAccountView: View {

    let targetType: AccountType
    let onComplete: (AddAccountResult) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)
                    SecureField("Password", text: $password)
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(.white)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    Button {
                        Task { await link() }
                    } label: {
                        HStack {
                            if isWorking { ProgressView().controlSize(.small).tint(.black) }
                            Text(isWorking ? "Verifying…" : "Link \(targetType.displayName) Account")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Color.cyan : Color.cyan.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit || isWorking)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.black)
            .navigationTitle("Link \(targetType.displayName) Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        onComplete(.cancelled)
                        dismiss()
                    }.foregroundColor(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 24))
                .foregroundColor(.cyan)
            Text("Sign in to your existing \(targetType.displayName.lowercased()) account.\nWe'll save it so toggling doesn't ask again.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
    }

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty }

    // MARK: - Link

    private func link() async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let previousActiveUID = Auth.auth().currentUser?.uid

        do {
            // Sign in to capture the credential. This will swap the
            // currently-signed-in user temporarily.
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            let uid = result.user.uid

            // Verify accountType on the user doc matches the slot we're
            // trying to fill. Reject if there's a mismatch — otherwise
            // we'd let a personal account be added as the "business"
            // slot which would break the toggle's invariant.
            let db = Firestore.firestore(database: Config.Firebase.databaseName)
            let doc = try await db.collection("users").document(uid).getDocument()
            let accountTypeRaw = doc.data()?["accountType"] as? String ?? "personal"
            let actualType = AccountType(rawValue: accountTypeRaw) ?? .personal
            guard actualType == targetType else {
                // Sign back into the previous account before erroring out.
                if let prevUID = previousActiveUID,
                   LinkedAccountManager.shared.accounts.contains(where: { $0.uid == prevUID }) {
                    try? await LinkedAccountManager.shared.switchTo(uid: prevUID)
                } else {
                    try? Auth.auth().signOut()
                }
                throw LinkedAccountError.wrongAccountType
            }

            let displayName = doc.data()?["displayName"] as? String ?? email
            let profileImageURL = doc.data()?["profileImageURL"] as? String

            let linked = LinkedAccount(
                uid: uid,
                email: email,
                accountType: actualType,
                displayName: displayName,
                profileImageURL: profileImageURL,
                provider: .emailPassword,
                addedAt: Date()
            )
            try LinkedAccountManager.shared.addEmailPasswordAccount(
                linked,
                email: email,
                password: password
            )

            // Restore previous session.
            if let prevUID = previousActiveUID, prevUID != uid {
                try await LinkedAccountManager.shared.switchTo(uid: prevUID)
            }

            onComplete(.added(linked))
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let prevUID = previousActiveUID,
               Auth.auth().currentUser?.uid != prevUID,
               LinkedAccountManager.shared.accounts.contains(where: { $0.uid == prevUID }) {
                try? await LinkedAccountManager.shared.switchTo(uid: prevUID)
            }
        }
    }
}
