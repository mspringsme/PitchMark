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
    @State private var otpCode: String = ""
    @State private var isSendingEmail: Bool = false
    @State private var isVerifyingOtp: Bool = false
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
                .frame(width: 250, height: 50)

                SignInWithAppleButton(.signIn, onRequest: { request in
                    authManager.prepareAppleSignIn(request)
                }, onCompletion: { result in
                    authManager.handleAppleSignIn(result: result)
                })
                .signInWithAppleButtonStyle(.black)
                .frame(width: 250, height: 50)

            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Email one-time code")
                    .font(.headline)

                TextField("you@email.com", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                Button(isSendingEmail ? "Sending..." : "Send Code") {
                    isSendingEmail = true
                    emailStatus = nil
                    authManager.requestEmailOtp(email: email) { result in
                        DispatchQueue.main.async {
                            isSendingEmail = false
                            switch result {
                            case .success:
                                emailStatus = "Check your email for a 6-digit code."
                            case .failure(let error):
                                emailStatus = error.localizedDescription
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSendingEmail || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                TextField("6-digit code", text: $otpCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Button(isVerifyingOtp ? "Verifying..." : "Verify Code") {
                    isVerifyingOtp = true
                    emailStatus = nil
                    authManager.verifyEmailOtp(email: email, code: otpCode) { result in
                        DispatchQueue.main.async {
                            isVerifyingOtp = false
                            switch result {
                            case .success:
                                emailStatus = "Signed in successfully."
                            case .failure(let error):
                                emailStatus = error.localizedDescription
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isVerifyingOtp ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let emailStatus {
                    Text(emailStatus)
                        .font(.caption)
                        .foregroundColor(emailStatus.hasPrefix("Signed") || emailStatus.hasPrefix("Check") ? .secondary : .red)
                }
            }
            .frame(maxWidth: 320)

            Spacer()
        }
        .padding()
    }

    private func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            print("No root view controller found")
            return
        }

        authManager.signInWithGoogle(presenting: rootViewController)
    }

}

//#Preview {
//    SignInView()
//        .environmentObject(AuthManager())
//}
