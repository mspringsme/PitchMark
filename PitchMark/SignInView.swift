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
    var onSkipDemo: (() -> Void)? = nil

    @State private var email: String = ""
    @State private var isSendingEmail: Bool = false
    @State private var emailStatus: String? = nil

    private var isDisplayApp: Bool {
        Bundle.main.bundleIdentifier == "app.Pitchmark-Display"
    }

    var body: some View {
        ZStack {
            if isDisplayApp {
                LinearGradient(
                    colors: [Color.blue.opacity(0.85), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                Image("LoginFieldBackground")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 28)

                    if isDisplayApp {
                        VStack(spacing: 6) {
                            Text("PM Display")
                                .font(.largeTitle.bold())
                            Text("PitchMark companion display")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.white)
                        .accessibilityElement(children: .combine)
                    } else {
                        Image("SoftballBaseballWtitle4")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .accessibilityLabel("PitchMark")
                    }

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

                        if authManager.isSigningInWithApple {
                            ProgressView("Signing in with Apple…")
                                .tint(.white)
                                .foregroundStyle(.white)
                        }

                        if let authenticationErrorMessage = authManager.authenticationErrorMessage {
                            Text(authenticationErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                    }
                    .frame(maxWidth: 420)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Email sign in")
                            .font(.headline)
                            .foregroundStyle(.white)

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
                                .foregroundColor(emailStatus.hasPrefix("Check") ? .white : .red)
                        }
                    }
                    .frame(maxWidth: 420)

                    if let onSkipDemo {
                        Button {
                            onSkipDemo()
                        } label: {
                            Text("Skip for Now")
                                .font(.headline)
                                .frame(maxWidth: 320, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .accessibilityHint("Opens a local demo with one game, one pitcher, and one grid key.")
                    }

                    Spacer(minLength: 24)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
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
