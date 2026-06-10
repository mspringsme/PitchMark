//
//  SignInView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/25/25.
//


import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email: String = ""
    @State private var isSendingEmail: Bool = false
    @State private var emailStatus: String? = nil

    var body: some View {
        VStack(spacing: 28) {
            Text("PitchMark")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.blue)

            VStack(spacing: 12) {
                GoogleSignInButton(
                    scheme: .light,
                    style: .standard,
                    state: .normal
                ) {
                    handleGoogleSignIn()
                }
                .frame(maxWidth: 320, minHeight: 50, maxHeight: 50)
                .accessibilityLabel("Sign in with Google")
                .accessibilityHint("Authenticates your PitchMark account using Google.")

                SignInWithAppleButton(.signIn, onRequest: { request in
                    authManager.prepareAppleSignIn(request)
                }, onCompletion: { result in
                    authManager.handleAppleSignIn(result: result)
                })
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: 320, minHeight: 50, maxHeight: 50)
                .accessibilityLabel("Sign in with Apple")
                .accessibilityHint("Authenticates your PitchMark account using Apple.")

            }
            .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                Text("Email sign in")
                    .font(.headline)

                TextField("you@email.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Email address")
                    .accessibilityHint("Enter the email where you want to receive a sign-in link.")

                Button(isSendingEmail ? "Sending..." : "Send Sign-In Link") {
                    isSendingEmail = true
                    emailStatus = nil
                    authManager.sendEmailSignInLink(email: email) { result in
                        DispatchQueue.main.async {
                            isSendingEmail = false
                            switch result {
                            case .success:
                                emailStatus = "Check your email for a sign-in link."
                            case .failure(let error):
                                emailStatus = error.localizedDescription
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isSendingEmail || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("Sends a sign-in link to your email.")

                if let emailStatus {
                    Text(emailStatus)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(emailStatus.hasPrefix("Check") ? .primary : .red)
                }
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding()
    }

    private func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            debugLog("No root view controller found")
            return
        }

        authManager.signInWithGoogle(presenting: rootViewController)
    }

}

//#Preview {
//    SignInView()
//        .environmentObject(AuthManager())
//}
