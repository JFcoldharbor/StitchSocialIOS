//
//  TeenLockedView.swift
//  StitchSocial
//
//  Placeholder gate shown to accounts in the teen lane until the kid-safe
//  experience is built.  Keeps the account active (so the user can
//  re-engage when the lane is ready) but blocks the main feed.
//

import SwiftUI
import FirebaseAuth

struct TeenLockedView: View {
    let displayName: String
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.1, blue: 0.2), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundColor(.cyan)

                Text("Hey \(displayName)!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("The teen experience is on its way.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Text("We're building a Stitch Social space designed for under-18 creators with safer feeds, age-appropriate content, and stronger privacy defaults. Your account is saved and we'll let you in as soon as it's ready.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button(action: signOutAndCallback) {
                    Text("Sign Out")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
    }

    private func signOutAndCallback() {
        try? Auth.auth().signOut()
        onSignOut()
    }
}

/// Hard-stop screen for under-13 sign-ups (COPPA compliance).
struct Under13BlockedView: View {
    let onAcknowledged: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)

                Text("Sorry, we can't create an account for you")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Stitch Social is for users 13 and older. Please come back when you're old enough to join.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button(action: onAcknowledged) {
                    Text("OK")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
        }
    }
}
