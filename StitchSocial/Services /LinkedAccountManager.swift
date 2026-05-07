//
//  LinkedAccountManager.swift
//  StitchSocial
//
//  Multi-account toggle. Lets a single human keep one personal AND one
//  business account on the device and swap between them without typing
//  a password. Mirrors Instagram's "Add Account" flow.
//
//  Constraints (intentional, see /linked-account discussion):
//   • Max 2 linked accounts: 1 personal + 1 business
//   • Each must have a different email (Firebase enforces unique emails)
//   • v1 supports email/password sign-in only — Apple/Google linking
//     comes in a follow-up because OAuth refresh tokens need separate
//     plumbing
//   • Local-only list — adding on iPhone doesn't auto-show on iPad
//     (cross-device sync is a separate concern; credentials never sync)
//
//  Toggle mechanism:
//   • signOut() then signIn(savedCreds) — sub-second round-trip
//   • Every service that listens to Auth.auth().addStateDidChangeListener
//     resets to the new uid automatically (HypeCoinCoordinator already
//     does this; rest are audited in the matching task)
//

import Foundation
import FirebaseAuth
import Security

// MARK: - Models

enum LinkedAuthProvider: String, Codable {
    case emailPassword = "email_password"
    // Future:
    // case apple
    // case google
}

struct LinkedAccount: Codable, Identifiable, Hashable {
    let uid: String
    let email: String
    let accountType: AccountType
    var displayName: String
    var profileImageURL: String?
    let provider: LinkedAuthProvider
    let addedAt: Date

    var id: String { uid }
}

enum LinkedAccountError: LocalizedError {
    case maxAccountsReached
    case duplicateAccountType
    case sameEmail
    case credentialsMissing
    case wrongAccountType

    var errorDescription: String? {
        switch self {
        case .maxAccountsReached:
            return "You can only link one personal and one business account."
        case .duplicateAccountType:
            return "An account of this type is already linked."
        case .sameEmail:
            return "The two linked accounts must use different email addresses."
        case .credentialsMissing:
            return "Saved credentials for this account couldn't be read."
        case .wrongAccountType:
            return "That account isn't the type you're trying to add."
        }
    }
}

// MARK: - Keychain

/// Tiny wrapper around the iOS Keychain that stores email+password per uid
/// for email/password-linked accounts. Keys live under the service id below;
/// removed when the linked account is removed or on logout-all.
fileprivate enum LinkedAccountKeychain {

    private static let service = "com.stitchsocial.linkedAccounts"

    static func save(uid: String, email: String, password: String) {
        let payload = "\(email)\u{1F}\(password)".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = payload
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(uid: String) -> (email: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        let parts = str.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    static func delete(uid: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: uid
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Manager

@MainActor
final class LinkedAccountManager: ObservableObject {

    static let shared = LinkedAccountManager()

    private static let listKey = "com.stitchsocial.linkedAccounts.list"

    @Published private(set) var accounts: [LinkedAccount] = []

    /// uid of the account currently signed in via Firebase Auth — kept in
    /// sync with auth state automatically.
    @Published private(set) var activeUID: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private init() {
        loadAccountsFromDisk()
        activeUID = Auth.auth().currentUser?.uid
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.activeUID = user?.uid }
        }
    }

    // MARK: - List + lookup

    var activeAccount: LinkedAccount? {
        guard let uid = activeUID else { return nil }
        return accounts.first { $0.uid == uid }
    }

    func otherAccount() -> LinkedAccount? {
        guard let uid = activeUID else { return accounts.first }
        return accounts.first { $0.uid != uid }
    }

    func hasLinked(accountType: AccountType) -> Bool {
        accounts.contains { $0.accountType == accountType }
    }

    var canAddAnother: Bool { accounts.count < 2 }

    /// Add the just-signed-in user to the linked list if it's not there
    /// already. Used by AuthService.signIn so existing users automatically
    /// get their current account "linked" without a separate explicit
    /// step — they just need to log in once with the new build.
    /// No-op when an account with the same uid already exists.
    func seedActiveIfMissing(
        uid: String,
        email: String,
        password: String,
        accountType: AccountType,
        displayName: String,
        profileImageURL: String?
    ) {
        guard !uid.isEmpty else { return }
        if accounts.contains(where: { $0.uid == uid }) { return }
        // Don't enforce maxAccounts here — if we somehow have 2 already
        // and a different uid signs in, that's a different problem; the
        // toggle will surface it.
        let entry = LinkedAccount(
            uid: uid,
            email: email,
            accountType: accountType,
            displayName: displayName,
            profileImageURL: profileImageURL,
            provider: .emailPassword,
            addedAt: Date()
        )
        LinkedAccountKeychain.save(uid: uid, email: email, password: password)
        accounts.append(entry)
        persist()
    }

    // MARK: - Add (call after a successful signUp/signIn for the linked account)

    /// Adds an email/password account to the linked list AFTER the
    /// caller has already authenticated it via Firebase Auth. The
    /// caller (Add-Account flow) is responsible for verifying that
    /// `account.accountType` matches the new user's actual Firestore
    /// `accountType` — this manager only persists what's handed in.
    func addEmailPasswordAccount(
        _ account: LinkedAccount,
        email: String,
        password: String
    ) throws {
        guard accounts.count < 2 else { throw LinkedAccountError.maxAccountsReached }
        if accounts.contains(where: { $0.accountType == account.accountType }) {
            throw LinkedAccountError.duplicateAccountType
        }
        if accounts.contains(where: { $0.email.lowercased() == email.lowercased() }) {
            throw LinkedAccountError.sameEmail
        }
        LinkedAccountKeychain.save(uid: account.uid, email: email, password: password)
        accounts.append(account)
        persist()
    }

    // MARK: - Remove

    func removeAccount(uid: String) {
        accounts.removeAll { $0.uid == uid }
        LinkedAccountKeychain.delete(uid: uid)
        persist()
    }

    /// Wipes all linked accounts on full logout. Called from AuthService.signOut
    /// when we want to fully forget the user (vs just toggling).
    func clearAll() {
        for acc in accounts { LinkedAccountKeychain.delete(uid: acc.uid) }
        accounts = []
        persist()
    }

    // MARK: - Switch

    /// Signs the current Firebase user out and re-signs in as `targetUID`.
    /// Throws if credentials aren't on this device. All services subscribed
    /// to `Auth.auth().addStateDidChangeListener` will reset to the new uid.
    func switchTo(uid: String) async throws {
        guard let account = accounts.first(where: { $0.uid == uid }) else {
            throw LinkedAccountError.credentialsMissing
        }
        guard let creds = LinkedAccountKeychain.load(uid: uid) else {
            throw LinkedAccountError.credentialsMissing
        }
        switch account.provider {
        case .emailPassword:
            try Auth.auth().signOut()
            _ = try await Auth.auth().signIn(withEmail: creds.email, password: creds.password)
        }
    }

    /// Convenience for the toggle button — switch to the other linked
    /// account if there is one. No-op if the user only has one account.
    func toggleActive() async throws {
        guard let other = otherAccount() else { return }
        try await switchTo(uid: other.uid)
    }

    // MARK: - Profile sync

    /// Update the cached display name / profile image for a linked account
    /// after the user edits their profile. Doesn't touch Firestore — pure
    /// local cache for the switcher UI.
    func updateProfileMetadata(uid: String, displayName: String?, profileImageURL: String?) {
        guard let idx = accounts.firstIndex(where: { $0.uid == uid }) else { return }
        if let dn = displayName { accounts[idx].displayName = dn }
        if let url = profileImageURL { accounts[idx].profileImageURL = url }
        persist()
    }

    // MARK: - Persistence (UserDefaults — non-sensitive metadata only)

    private func loadAccountsFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: Self.listKey) else { return }
        if let decoded = try? JSONDecoder().decode([LinkedAccount].self, from: data) {
            accounts = decoded
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: Self.listKey)
    }
}
